# frozen_string_literal: true

class DividendPaymentProcessor
  class PaymentProcessingError < StandardError; end

  def initialize(dividend_round)
    @dividend_round = dividend_round
    @company = dividend_round.company
  end

  def process
    return if @dividend_round.processed_at.present?

    ActiveRecord::Base.transaction do
      charge = charge_company
      create_investor_payouts
      @dividend_round.update!(
        processed_at: Time.current,
        stripe_charge_id: charge.id
      )
      send_dividend_notifications
    end
  rescue StandardError => e
    Rails.logger.error("Failed to process dividend payments: #{e.message}")
    raise PaymentProcessingError, "Failed to process payments: #{e.message}"
  end

  private

  def charge_company
    fee_per_dividend = 0.30
    total_fee_cents = (@dividend_round.total_amount_in_usd * 0.029 * 100).round +
                      (@dividend_round.dividends.count * fee_per_dividend * 100).round
    total_amount_cents = (@dividend_round.total_amount_in_usd * 100).round + total_fee_cents

    Stripe::Charge.create(
      amount: total_amount_cents,
      currency: 'usd',
      customer: @company.stripe_customer_id,
      description: "Dividend payment for #{@dividend_round.issuance_date}",
      metadata: {
        dividend_round_id: @dividend_round.id,
        company_id: @company.id
      }
    )
  end

  def create_investor_payouts
    @dividend_round.dividends.each do |dividend|
      investor = dividend.company_investor.user

      transfer = Stripe::Transfer.create({
        amount: dividend.total_amount_in_cents,
        currency: 'usd',
        destination: investor.stripe_account_id,
        description: "Dividend payment for #{investor.legal_name}",
        metadata: {
          dividend_id: dividend.id,
          investor_id: investor.id
        }
      })

      dividend.update!(stripe_transfer_id: transfer.id)

      initiate_wise_transfer(dividend, investor) if investor.wise_recipient.present?
    end
  end

  def initiate_wise_transfer(dividend, investor)
    wise_recipient = investor.wise_recipient
    return unless wise_recipient

    quote = create_wise_quote(
      source_currency: 'USD',
      target_currency: wise_recipient.currency,
      source_amount: dividend.total_amount_in_cents / 100.0,
      target_account: wise_recipient.recipient_id
    )

    transfer = create_wise_transfer(
      quote_id: quote['id'],
      target_account: wise_recipient.recipient_id,
      customer_transaction_id: "DIVIDEND_#{dividend.id}",
      reference: "Dividend payment for #{investor.legal_name}",
      transfer_purpose: "Dividend payment"
    )

    dividend.update!(
      wise_transfer_id: transfer['id'],
      wise_quote_id: quote['id'],
      transfer_fee_in_usd: quote['fee']
    )

    fund_wise_transfer(transfer['id']) if transfer['status'] == 'unfunded'

    transfer
  rescue StandardError => e
    Rails.logger.error("Failed to initiate Wise transfer for dividend #{dividend.id}: #{e.message}")
    raise PaymentProcessingError, "Failed to initiate international transfer: #{e.message}"
  end

  def create_wise_quote(source_currency:, target_currency:, source_amount:, target_account:)
    response = wise_client.post('v3/profiles/me/quotes', {
      sourceCurrency: source_currency,
      targetCurrency: target_currency,
      sourceAmount: source_amount,
      targetAccount: target_account,
      preferredPayIn: 'BALANCE',
      payOut: 'BANK_TRANSFER'
    }.to_json, 'Content-Type' => 'application/json')

    JSON.parse(response.body)
  end

  def create_wise_transfer(quote_id:, target_account:, customer_transaction_id:, reference:, transfer_purpose:)
    response = wise_client.post('v1/transfers', {
      targetAccount: target_account,
      quoteUuid: quote_id,
      customerTransactionId: customer_transaction_id,
      details: {
        reference: reference,
        transferPurpose: transfer_purpose,
        sourceOfFunds: "Dividend payment"
      }
    }.to_json, 'Content-Type' => 'application/json')

    JSON.parse(response.body)
  end

  def fund_wise_transfer(transfer_id)
    wise_client.post("v3/profiles/me/transfers/#{transfer_id}/payments", {
      type: 'BALANCE'
    }.to_json, 'Content-Type' => 'application/json')
  end

  def wise_client
    @wise_client ||= Faraday.new(
      url: 'https://api.transferwise.com',
      headers: {
        'Authorization' => "Bearer #{ENV['WISE_API_KEY']}",
        'Content-Type' => 'application/json'
      }
    ) do |f|
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end

  def send_dividend_notifications
    @dividend_round.dividends.each do |dividend|
      investor = dividend.company_investor.user
      DividendMailer.dividend_issued(dividend, investor).deliver_later
    end
  end
end
