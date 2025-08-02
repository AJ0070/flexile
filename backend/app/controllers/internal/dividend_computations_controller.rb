# frozen_string_literal: true

class Internal::DividendComputationsController < Internal::BaseController
  before_action :set_company
  before_action :set_dividend_computation, only: [:show, :finalize]
  after_action :verify_authorized

  def create
    authorize :dividend_computation

    @dividend_computation = DividendComputationGeneration.new(
      @company,
      amount_in_usd: dividend_params[:amount_in_usd],
      dividends_issuance_date: dividend_params[:dividends_issuance_date] || Date.current,
      return_of_capital: ActiveModel::Type::Boolean.new.cast(dividend_params[:return_of_capital])
    ).process

    if dividend_params[:release_form].present?
      @dividend_computation.update!(release_form: dividend_params[:release_form])
    end

    render json: {
      success: true,
      dividend_computation: dividend_computation_presenter(@dividend_computation)
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def show
    authorize @dividend_computation
    render json: {
      success: true,
      dividend_computation: dividend_computation_presenter(@dividend_computation)
    }
  end

  def finalize
    authorize @dividend_computation

    ActiveRecord::Base.transaction do
      if @dividend_computation.dividends_issuance_date > Date.current
        @dividend_computation.update!(ready_for_payment: true)
      else
        @dividend_computation.generate_dividends
        # TODO: Add logic to pull money from customer and initiate Stripe/Wise transfers
      end
    end

    render json: { success: true }
  rescue StandardError => e
    Rails.logger.error("Failed to finalize dividend computation: #{e.message}")
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_company
    @company = Current.company || Company.find(params[:company_id])
  end

  def set_dividend_computation
    @dividend_computation = @company.dividend_computations.find(params[:id])
  end

  def dividend_params
    params.require(:dividend_computation).permit(
      :amount_in_usd,
      :dividends_issuance_date,
      :return_of_capital,
      :release_form
    )
  end

  def dividend_computation_presenter(dividend_computation)
    {
      id: dividend_computation.id,
      company_id: dividend_computation.company_id,
      total_amount_in_usd: dividend_computation.total_amount_in_usd,
      dividends_issuance_date: dividend_computation.dividends_issuance_date,
      return_of_capital: dividend_computation.return_of_capital,
      created_at: dividend_computation.created_at,
      outputs: dividend_computation.dividend_computation_outputs.map do |output|
        {
          id: output.id,
          company_investor_id: output.company_investor_id,
          investor_name: output.investor_name || output.company_investor&.user&.legal_name,
          share_class: output.share_class,
          number_of_shares: output.number_of_shares,
          total_amount_in_usd: output.total_amount_in_usd,
          preferred_dividend_amount_in_usd: output.preferred_dividend_amount_in_usd,
          dividend_amount_in_usd: output.dividend_amount_in_usd
        }
      end
    }
  end
end
