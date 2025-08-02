# frozen_string_literal: true

class DividendFinalizationService
  MINIMUM_ISSUANCE_NOTICE_DAYS = 10

  def initialize(dividend_computation, issuance_date)
    @computation = dividend_computation
    @issuance_date = issuance_date.to_date
    validate_issuance_date
  end

  def process
    ActiveRecord::Base.transaction do
      @computation.generate_dividends
      @computation.update!(dividends_issuance_date: @issuance_date)

      pull_funds_from_customer
      transfer_funds_to_payout_account

      send_investor_emails
    end
  rescue => e
    Rails.logger.error "Dividend finalization failed for computation ##{@computation.id}: #{e.message}"
    raise
  end

  private

  def validate_issuance_date
    if @issuance_date < Date.current + MINIMUM_ISSUANCE_NOTICE_DAYS
      raise ArgumentError, "Dividend issuance date must be at least #{MINIMUM_ISSUANCE_NOTICE_DAYS} days in the future"
    end
  end

  def pull_funds_from_customer
    customer = @computation.company.stripe_customer
    amount = (@computation.total_amount_in_usd * 100).to_i

    charge = Stripe::Charge.create(
      customer: customer.id,
      amount: amount,
      currency: 'usd',
      description: "Dividend payment for #{@computation.dividends_issuance_date}",
      metadata: {
        dividend_computation_id: @computation.id,
        company_id: @computation.company_id,
        type: 'dividend_charge'
      }
    )

    charge
  end

  def transfer_funds_to_payout_account
    max_retries = 3
    retry_count = 0
    last_error = nil

    begin
      balance = Stripe::Balance.retrieve
      available_balance = balance.available.first.amount
      transfer_amount = (@computation.total_amount_in_usd * 100).to_i

      if available_balance < transfer_amount
        raise "Insufficient balance in Stripe account. Available: #{available_balance / 100.0}, Required: #{transfer_amount / 100.0}"
      end

      wise_recipient = @computation.company.dividend_wise_recipient
      raise 'No Wise recipient account configured for dividends' unless wise_recipient.present?
      wise_recipient_id = wise_recipient.recipient_id

      transfer = Stripe::Transfer.create({
        amount: transfer_amount,
        currency: 'usd',
        destination: wise_recipient_id,
        description: "Dividend payout for #{@computation.company.name} - #{@computation.dividends_issuance_date}",
        metadata: {
          dividend_computation_id: @computation.id,
          company_id: @computation.company_id,
          purpose: 'dividend_payout'
        }
      })

      Rails.logger.info "Successfully transferred #{transfer_amount / 100.0} USD to Wise for dividend computation ##{@computation.id}"

      transfer

    rescue Stripe::RateLimitError, Stripe::APIConnectionError, Stripe::StripeError => e
      if retry_count < max_retries
        retry_count += 1
        retry_delay = 2 ** retry_count
        Rails.logger.warn "Stripe transfer attempt #{retry_count} failed. Retrying in #{retry_delay} seconds. Error: #{e.message}"
        sleep(retry_delay)
        retry
      else
        last_error = e
      end
    rescue => e
      last_error = e
    end

    error_message = "Failed to transfer funds to Wise after #{max_retries} attempts: #{last_error&.message}"
    Rails.logger.error(error_message)
    raise error_message
  end

  def send_investor_emails
    @computation.dividend.investor_dividend_rounds.each do |investor_round|
      CompanyInvestorMailer.with(
        investor_dividend_round_id: investor_round.id
      ).dividend_issued.deliver_later
    end
  end
end