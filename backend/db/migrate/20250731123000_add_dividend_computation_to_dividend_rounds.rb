# frozen_string_literal: true

class AddDividendComputationToDividendRounds < ActiveRecord::Migration[7.0]
  def change
    add_reference :dividend_rounds, :dividend_computation, null: true, foreign_key: true
  end
end
