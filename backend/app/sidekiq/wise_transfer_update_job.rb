# frozen_string_literal: true

class WiseTransferUpdateJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform(params)
    Rails.logger.info("Processing Wise Transfer webhook: #{params}")

    profile_id = params.dig("data", "resource", "profile_id").to_s
    return if profile_id != WISE_PROFILE_ID && WiseCredential.where(profile_id:).none?

    if params["event_type"] == "transfers#refund"
      handle_refund(params)
    else
      handle_state_change(params)
    end
  end

  private

  def handle_refund(params)
    transfer_id = params.dig("data", "resource", "transferId")
    return if transfer_id.blank?

    payment = find_payment(transfer_id)
    return unless payment

    update_payment_status(payment, Payment::FAILED, params)
  end

  def handle_state_change(params)
    transfer_id = params.dig("data", "resource", "id")
    return if transfer_id.blank?

    payment = find_payment(transfer_id)
    return unless payment

    current_state = params.dig("data", "current_state")
    payment.update!(wise_transfer_status: current_state)

    if payment.in_failed_state?
      update_payment_status(payment, Payment::FAILED, params)
    elsif payment.in_processing_state?
      if payment.is_a?(Payment)
        payment.invoice.update!(status: Invoice::PROCESSING)
      elsif payment.is_a?(DividendPayment)
        DividendPaymentTransferUpdate.new(payment, params).process
      end
    elsif current_state == Payments::Wise::OUTGOING_PAYMENT_SENT
      update_payment_status(payment, Payment::SUCCEEDED, params)
    end
  end

  def find_payment(transfer_id)
    payment = Payment.find_by(wise_transfer_id: transfer_id)
    return payment if payment.present?

    equity_buyback_payment = EquityBuybackPayment.wise.find_by(transfer_id: transfer_id)
    return equity_buyback_payment if equity_buyback_payment.present?

    DividendPayment.wise.find_by(transfer_id: transfer_id)
  end

  def update_payment_status(payment, status, params)
    return if payment.status == status

    api_service = Wise::PayoutApi.new(wise_credential: payment.wise_credential)
    transfer_id = payment.is_a?(Payment) ? payment.wise_transfer_id : payment.transfer_id

    if status == Payment::FAILED
      payment.update!(status: Payment::FAILED)
      if payment.is_a?(Payment)
        payment.invoice.update!(status: Invoice::FAILED)
        amount_cents = api_service.get_transfer(transfer_id: transfer_id)["sourceValue"] * -100
        payment.balance_transactions.create!(company: payment.company, amount_cents: amount_cents, transaction_type: BalanceTransaction::PAYMENT_FAILED)
      elsif payment.is_a?(EquityBuybackPayment)
        EquityBuybackPaymentTransferUpdate.new(payment, params).process
      elsif payment.is_a?(DividendPayment)
        DividendPaymentTransferUpdate.new(payment, params).process
      end
    elsif status == Payment::SUCCEEDED
      amount = api_service.get_transfer(transfer_id: transfer_id)["targetValue"]
      estimate = Time.zone.parse(api_service.delivery_estimate(transfer_id: transfer_id)["estimatedDeliveryDate"])
      payment.update!(status: Payment::SUCCEEDED, wise_transfer_amount: amount, wise_transfer_estimate: estimate)
      if payment.is_a?(Payment)
        payment.invoice.mark_as_paid!(timestamp: Time.zone.parse(params.dig("data", "occurred_at")), payment_id: payment.id)
      elsif payment.is_a?(DividendPayment)
        DividendPaymentTransferUpdate.new(payment, params).process
      end
    end
  end
end