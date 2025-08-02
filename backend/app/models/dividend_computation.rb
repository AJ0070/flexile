# frozen_string_literal: true

class DividendComputation < ApplicationRecord
  include ExternalId

  belongs_to :company
  has_many :dividend_computation_outputs, dependent: :destroy

  validates :total_amount_in_usd, presence: true, numericality: { greater_than: 0 }
  validates :dividends_issuance_date, presence: true
  validates :ready_for_payment, inclusion: { in: [true, false] }
  validate :issuance_date_not_in_past, on: :create

  scope :pending, -> { where(ready_for_payment: false) }
  scope :ready_for_payment, -> { where(ready_for_payment: true, dividends_issuance_date: ..Date.current) }

  def dividend_rounds
    return DividendRound.where(id: @created_dividend_round.id) if @created_dividend_round
    
    return DividendRound.none if external_id.blank?
    
    rounds = company.dividend_rounds.where("external_id = ? OR external_id LIKE ?", "round_#{external_id}", "round_#{external_id}%")
    
    if rounds.empty?
      reload
      rounds = company.dividend_rounds.where("external_id = ? OR external_id LIKE ?", "round_#{external_id}", "round_#{external_id}%")
    end
    
    rounds
  end

  def to_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        "Investor",
        "Share class",
        "Number of shares",
        "Hurdle rate",
        "Original issue price (USD)",
        "Common dividend amount (USD)",
        "Preferred dividend amount (USD)",
        "Total amount (USD)"
      ]
      
      dividend_computation_outputs.order(:id).find_each do |output|
        investor_name = if output.company_investor&.user
                          output.company_investor.user.legal_name
                        elsif output.investor_name
                          output.investor_name
                        else
                          'Unknown Investor'
                        end

        csv << [
          investor_name,
          output.share_class,
          output.number_of_shares,
          output.hurdle_rate,
          output.original_issue_price_in_usd,
          output.dividend_amount_in_usd,
          output.preferred_dividend_amount_in_usd,
          output.total_amount_in_usd
        ]
      end
    end
  end

  def to_per_investor_csv
    share_dividends, safe_dividends = dividends_info

    CSV.generate(headers: true) do |csv|
      csv << [
        "Investor",
        "Investor ID",
        "Number of shares",
        "Amount (USD)"
      ]

      share_dividends.each do |investor_id, details|
        company_investor = CompanyInvestor.find_by(id: investor_id)
        next unless company_investor
        
        investor = company_investor.user

        csv << [
          investor.legal_name,
          investor_id,
          details[:number_of_shares],
          details[:total_amount]
        ]
      end

      safe_dividends.each do |investor_name, details|
        csv << [
          investor_name,
          nil,
          details[:number_of_shares],
          details[:total_amount]
        ]
      end
    end
  end

  def to_final_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        "Investor",
        "Investor ID",
        "Number of shares",
        "Amount (USD)"
      ]

      share_dividends, safe_dividends = dividends_info

      share_dividends.each do |investor_id, details|
        company_investor = CompanyInvestor.find_by(id: investor_id)
        next unless company_investor
        
        investor = company_investor.user

        csv << [
          investor.legal_name,
          investor_id,
          details[:number_of_shares],
          details[:total_amount]
        ]
      end

      safe_dividends.each do |investor_name, details|
        investment = company.convertible_investments.find_by(entity_name: investor_name)
        next unless investment

        investment.convertible_securities.each do |security|
          company_investor = security.company_investor
          next unless company_investor
          
          investment_in_usd = investment.amount_in_cents.to_d / 100.to_d
          security_in_usd = security.principal_value_in_cents.to_d / 100.to_d
          
          proportional_amount = 0
          if investment_in_usd > 0
            proportional_amount = (details[:total_amount] / investment_in_usd * security_in_usd).round(2)
          end

          display_name = company_investor.user&.legal_name || investor_name

          csv << [
            display_name,
            company_investor.id,
            nil,
            proportional_amount
          ]
        end
      end
    end
  end

  def generate_dividends
    data = data_for_dividend_creation

    if external_id.blank?
      computation_external_id = "comp_#{SecureRandom.hex(8)}"
      update_column(:external_id, computation_external_id)
      reload
    else
      computation_external_id = external_id
    end

    total_amount_in_cents = (BigDecimal(total_amount_in_usd.to_s) * 100).round.to_i

    @created_dividend_round = company.dividend_rounds.create!(
      issued_at: dividends_issuance_date,
      number_of_shares: data.sum { |d| d[:number_of_shares].to_i },
      number_of_shareholders: data.map { |d| d[:company_investor_id] }.uniq.count,
      status: "Issued",
      total_amount_in_cents: total_amount_in_cents,
      return_of_capital: return_of_capital,
      external_id: "round_#{computation_external_id}"
    )

    data.each do |dividend_attrs|
      company_investor = CompanyInvestor.find_by(id: dividend_attrs[:company_investor_id])
      next unless company_investor

      total_cents = (BigDecimal(dividend_attrs[:total_amount].to_s) * 100).round.to_i
      qualified_cents = (BigDecimal(dividend_attrs[:qualified_dividends_amount].to_s) * 100).round.to_i

      @created_dividend_round.dividends.create!(
        company: company,
        company_investor: company_investor,
        total_amount_in_cents: total_cents,
        qualified_amount_cents: qualified_cents,
        number_of_shares: dividend_attrs[:number_of_shares],
        status: "Issued"
      )
    end
    
    @created_dividend_round
  end

  def dividends_info
    share_dividends = Hash.new { |h, k| h[k] = { number_of_shares: 0, total_amount: 0.to_d, qualified_dividends_amount: 0.to_d } }
    safe_dividends = Hash.new { |h, k| h[k] = { number_of_shares: 0, total_amount: 0.to_d, qualified_dividends_amount: 0.to_d } }

    dividend_computation_outputs.find_each do |output|
      if output.investor_name.present?
        safe_dividends[output.investor_name][:number_of_shares] += output.number_of_shares
        safe_dividends[output.investor_name][:total_amount] += output.total_amount_in_usd
        safe_dividends[output.investor_name][:qualified_dividends_amount] += output.qualified_dividend_amount_usd
      else
        share_dividends[output.company_investor_id][:number_of_shares] += output.number_of_shares
        share_dividends[output.company_investor_id][:total_amount] += output.total_amount_in_usd
        share_dividends[output.company_investor_id][:qualified_dividends_amount] += output.qualified_dividend_amount_usd
      end
    end

    [share_dividends, safe_dividends]
  end

  private

  def issuance_date_not_in_past
    return if dividends_issuance_date.blank? || dividends_issuance_date >= Date.current

    errors.add(:dividends_issuance_date, "can't be in the past")
  end

  def data_for_dividend_creation
    data = []
    share_dividends, safe_dividends = dividends_info

    share_dividends.each do |company_investor_id, info|
      data << {
        company_investor_id: company_investor_id,
        total_amount: info[:total_amount],
        qualified_dividends_amount: info[:qualified_dividends_amount],
        number_of_shares: info[:number_of_shares]
      }
    end

    safe_dividends.each do |investor_name, info|
      investment = company.convertible_investments.find_by(entity_name: investor_name)
      next unless investment

      investment_in_usd = investment.amount_in_cents.to_d / 100.to_d
      next if investment_in_usd.zero?

      investment.convertible_securities.each do |security|
        security_in_usd = security.principal_value_in_cents.to_d / 100.to_d

        data << {
          company_investor_id: security.company_investor_id,
          qualified_dividends_amount: (info[:qualified_dividends_amount] / investment_in_usd * security_in_usd).round(2),
          total_amount: (info[:total_amount] / investment_in_usd * security_in_usd).round(2),
          number_of_shares: nil
        }
      end
    end

    data
  end
end