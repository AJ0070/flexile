# frozen_string_literal: true

class DividendComputationPolicy < ApplicationPolicy
  def create?
    company_administrator?
  end

  def show?
    company_administrator? || record.company_investors.exists?(user: user)
  end

  def finalize?
    company_administrator?
  end

  private

  def company_administrator?
    user.company_administrator?(record.company)
  end
end
