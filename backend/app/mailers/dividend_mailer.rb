# frozen_string_literal: true

class DividendMailer < ApplicationMailer
  def dividend_issued(dividend, investor)
    @dividend = dividend
    @investor = investor
    @company = dividend.company_investor.company
    
    subject = "Dividend Payment Notification - #{@company.name}"
    
    mail(
      to: @investor.email,
      subject: subject,
      template_name: 'dividend_issued'
    )
  end
  
  def dividend_round_created(dividend_round, investor)
    @dividend_round = dividend_round
    @investor = investor
    @company = dividend_round.company
    
    subject = "New Dividend Round - #{@company.name}"
    
    mail(
      to: @investor.email,
      subject: subject,
      template_name: 'dividend_round_created'
    )
  end
end
