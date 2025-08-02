# frozen_string_literal: true

class PrepareDailyDividendsJob
  include Sidekiq::Worker
  sidekiq_options queue: 'default', retry: 3

  def perform
    dividend_rounds = DividendRound
      .joins(:dividends)
      .where("dividends.dividend_issuance_date <= ?", Date.current)
      .where(ready_for_payment: false, status: 'pending')
      .distinct

    dividend_rounds.find_each do |round|
      process_round(round)
    end
  end

  private

  def process_round(round)
    round.with_lock do
      return if round.ready_for_payment? || round.status != 'pending'

      Rails.logger.info "[PrepareDailyDividendsJob] Marking dividend round ##{round.id} as ready for payment"

      round.update!(
        ready_for_payment: true,
        processed_at: Time.current,
        status: 'processing'
      )
    end
  rescue StandardError => e
    Rails.logger.error(
      "[PrepareDailyDividendsJob] Failed to process dividend round ##{round&.id}: #{e.message}\n" \
      "#{e.backtrace.join("\n")}"
    )

    if round&.persisted?
      round.update_columns(
        status: 'failed',
        error_message: e.message.truncate(255)
      )
    end

    raise e
  end
end