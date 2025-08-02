# frozen_string_literal: true

class ProcessDividendComputationsJob < ApplicationJob
  queue_as :default

  def perform
    DividendComputation.ready_for_payment.find_each do |computation|
      next if computation.dividend_rounds.any?

      begin
        computation.with_lock do
          computation.generate_dividends
        end
      rescue StandardError => e
        Rails.logger.error("Failed to process dividend computation #{computation.id}: #{e.message}")
        # TODO: notify admins of the failure
      end
    end
  end
end
