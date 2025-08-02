# frozen_string_literal: true

class AddPaymentMethodToDividends < ActiveRecord::Migration[7.0]
  def change
    add_column :dividends, :payment_method, :string
    add_column :dividends, :payment_date, :datetime

    add_index :dividends, :payment_method

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE dividends
          SET payment_method = 'Stripe',
              payment_date = updated_at
          WHERE (stripe_transfer_id IS NOT NULL OR wise_transfer_id IS NOT NULL)
        SQL
      end
    end
  end
end
