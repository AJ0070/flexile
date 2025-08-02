# frozen_string_literal: true

class CleanupDeprecatedFlags < ActiveRecord::Migration[7.0]
  def up
    if column_exists?(:companies, :dividends_allowed)
      remove_column :companies, :dividends_allowed
    end

    if column_exists?(:companies, :irs_tax_forms)
      remove_column :companies, :irs_tax_forms
    end

    unless column_exists?(:dividend_computations, :ready_for_payment)
      add_column :dividend_computations, :ready_for_payment, :boolean, default: false, null: false
    end

    unless column_exists?(:dividend_rounds, :stripe_charge_id)
      add_column :dividend_rounds, :stripe_charge_id, :string
      add_index :dividend_rounds, :stripe_charge_id, unique: true
    end

    unless column_exists?(:dividend_rounds, :processing_fee_in_cents)
      add_column :dividend_rounds, :processing_fee_in_cents, :integer
    end

    unless column_exists?(:dividend_rounds, :processed_at)
      add_column :dividend_rounds, :processed_at, :datetime
    end

    unless column_exists?(:dividends, :stripe_transfer_id)
      add_column :dividends, :stripe_transfer_id, :string
      add_index :dividends, :stripe_transfer_id, unique: true
    end

    unless column_exists?(:dividends, :wise_transfer_id)
      add_column :dividends, :wise_transfer_id, :string
      add_index :dividends, :wise_transfer_id, unique: true
    end

    unless column_exists?(:dividends, :wise_quote_id)
      add_column :dividends, :wise_quote_id, :string
      add_index :dividends, :wise_quote_id
    end

    unless column_exists?(:dividends, :transfer_fee_in_usd)
      add_column :dividends, :transfer_fee_in_usd, :decimal, precision: 10, scale: 2
    end
  end

  def down
    unless column_exists?(:companies, :dividends_allowed)
      add_column :companies, :dividends_allowed, :boolean, default: false
    end

    unless column_exists?(:companies, :irs_tax_forms)
      add_column :companies, :irs_tax_forms, :boolean, default: false
    end

    remove_column :dividend_computations, :ready_for_payment if column_exists?(:dividend_computations, :ready_for_payment)

    if column_exists?(:dividend_rounds, :stripe_charge_id)
      remove_index :dividend_rounds, :stripe_charge_id
      remove_column :dividend_rounds, :stripe_charge_id
    end

    remove_column :dividend_rounds, :processing_fee_in_cents if column_exists?(:dividend_rounds, :processing_fee_in_cents)
    remove_column :dividend_rounds, :processed_at if column_exists?(:dividend_rounds, :processed_at)

    if column_exists?(:dividends, :stripe_transfer_id)
      remove_index :dividends, :stripe_transfer_id
      remove_column :dividends, :stripe_transfer_id
    end

    if column_exists?(:dividends, :wise_transfer_id)
      remove_index :dividends, :wise_transfer_id
      remove_column :dividends, :wise_transfer_id
    end

    if column_exists?(:dividends, :wise_quote_id)
      remove_index :dividends, :wise_quote_id
      remove_column :dividends, :wise_quote_id
    end

    remove_column :dividends, :transfer_fee_in_usd if column_exists?(:dividends, :transfer_fee_in_usd)
  end
end
