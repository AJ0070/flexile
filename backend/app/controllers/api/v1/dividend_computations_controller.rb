# frozen_string_literal: true

class Api::V1::DividendComputationsController < Api::V1::BaseController
  before_action :set_dividend_computation, only: [:show, :details, :finalize]

  def create
    computation = DividendComputationGeneration.new(
      company: current_company,
      dividend_date: dividend_params[:dividend_date],
      dividend_amount: dividend_params[:amount],
      return_of_capital: dividend_params[:is_return_of_capital],
      investor_release_form: dividend_params[:investor_release_form]
    ).process

    if computation.persisted?
      render json: computation, status: :created
    else
      render json: { errors: computation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render json: @dividend_computation
  end

  def details
    render json: format_investor_details(@dividend_computation), status: :ok
  end

  def finalize
    if @dividend_computation.dividend.present?
      render json: { message: 'This dividend has already been finalized.' }, status: :ok
      return
    end

    DividendFinalizationService.new(
      @dividend_computation,
      finalize_params[:dividend_issuance_date]
    ).process

    render json: { message: 'Dividend finalization process has been initiated.' }, status: :ok
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue => e
    render json: { errors: ['An unexpected error occurred during finalization.'] }, status: :internal_server_error
  end

  private

  def set_dividend_computation
    @dividend_computation = DividendComputation.find(params[:id])
  end

  def dividend_params
    params.require(:dividend_computation).permit(
      :dividend_date,
      :amount,
      :is_return_of_capital,
      :investor_release_form
    )
  end

  def finalize_params
    params.require(:dividend_computation).permit(:dividend_issuance_date)
  end

  def format_investor_details(computation)
    csv_data = computation.to_per_investor_csv.csv_array
    investors = csv_data.map do |row|
      {
        investor_name: row['Investor Name'],
        payout_amount: row['Amount']
      }
    end

    {
      id: computation.id,
      dividend_date: computation.dividend_date,
      total_amount: computation.amount,
      investors: investors
    }
  end
end