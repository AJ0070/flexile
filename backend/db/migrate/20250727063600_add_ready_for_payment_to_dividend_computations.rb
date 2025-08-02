# frozen_string_literal: true

class AddReadyForPaymentToDividendComputations < ActiveRecord::Migration[8.0]
  def change
    add_column :dividend_computations, :ready_for_payment, :boolean, default: false, null: false
  end
end
