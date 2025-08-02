# frozen_string_literal: true

class StripePaymentProcessor
  class PaymentProcessingError < StandardError; end

  def initialize(dividend_round)
    @dividend_round = dividend_round
    @company = dividend_round.company
  end

  def process
    return if @dividend_round.stripe_charge_id.present?

    ActiveRecord::Base.transaction do
      fee_per_dividend = 0.30
      total_fee_cents = (@dividend_round.total_amount_in_usd * 0.029 * 100).round +
                       (@dividend_round.dividends.count * fee_per_dividend * 100).round
      total_amount_cents = (@dividend_round.total_amount_in_usd * 100).round + total_fee_cents

      charge = create_charge(total_amount_cents)

      create_investor_transfers

      @dividend_round.update!(
        stripe_charge_id: charge.id,
        processing_fee_in_cents: total_fee_cents,
        processed_at: Time.current
      )

      send_notifications

      charge
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("Stripe error processing dividend round #{@dividend_round.id}: #{e.message}")
    raise PaymentProcessingError, "Payment processing failed: #{e.message}"
  rescue StandardError => e
    Rails.logger.error("Error processing dividend round #{@dividend_round.id}: #{e.message}")
    raise PaymentProcessingError, "An error occurred while processing payments: #{e.message}"
  end

  private

  def create_charge(amount_cents)
    Stripe::Charge.create(
      amount: amount_cents,
      currency: 'usd',
      customer: @company.stripe_customer_id,
      description: "Dividend payment for #{@dividend_round.issuance_date}",
      metadata: {
        dividend_round_id: @dividend_round.id,
        company_id: @company.id,
        type: 'dividend_payment'
      },
      transfer_group: "DIVIDEND_#{@dividend_round.id}"
    )
  end

  def create_investor_transfers
    @dividend_round.dividends.each do |dividend|
      investor = dividend.company_investor.user
      next unless investor.stripe_account_id.present? && dividend.total_amount_in_cents.positive?

      transfer = Stripe::Transfer.create({
        amount: dividend.total_amount_in_cents,
        currency: 'usd',
        destination: investor.stripe_account_id,
        transfer_group: "DIVIDEND_#{@dividend_round.id}",
        description: "Dividend payment for #{investor.legal_name}",
        metadata: {
          dividend_id: dividend.id,
          investor_id: investor.id,
          company_id: @company.id
        }
      })

      dividend.update!(stripe_transfer_id: transfer.id)

      if investor.wise_recipient.present?
        DividendPaymentProcessor.new(@dividend_round).initiate_wise_transfer(dividend, investor)
      end
    end
  end

  def send_notifications
    @dividend_round.dividends.each do |dividend|
      investor = dividend.company_investor.user
      DividendMailer.dividend_issued(dividend, investor).deliver_later
    end

    @company.company_administrators.includes(:user).each do |admin|
      AdminMailer.dividend_round_processed(@dividend_round, admin.user).deliver_later
    end
  end
end
