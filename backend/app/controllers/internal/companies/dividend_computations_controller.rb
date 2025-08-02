# frozen_string_literal: true

class Internal::Companies::DividendComputationsController < Internal::Companies::BaseController
    def create
      authorize! @company, :create_dividend_computation?, with: DividendComputationPolicy
      dividend_computation = DividendComputationGeneration.new(
        company: @company,
        dividends_issuance_date: dividend_computation_params[:dividend_date],
        total_amount_in_cents: Money.from_amount(dividend_computation_params[:amount].to_f).cents,
        return_of_capital: dividend_computation_params[:is_return_of_capital],
        investor_release_form: dividend_computation_params[:investor_release_form]
      ).process

      if dividend_computation.persisted?
        render json: dividend_computation, status: :created
      else
        render json: { errors: dividend_computation.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def dividend_computation_params
      params.require(:dividend_computation).permit(
        :dividend_date,
        :amount,
        :is_return_of_capital,
        :investor_release_form
      )
    end
  end
