class AddReadyForPaymentToDividendRounds < ActiveRecord::Migration[8.0]
  def change
    add_column :dividend_rounds, :ready_for_payment, :boolean, default: false, null: false
  end
end