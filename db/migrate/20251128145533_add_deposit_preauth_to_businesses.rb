# frozen_string_literal: true

class AddDepositPreauthToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :rental_deposit_preauth_enabled, :boolean, default: false, null: false
    
    add_index :businesses, :rental_deposit_preauth_enabled,
      where: 'rental_deposit_preauth_enabled = true',
      name: 'index_businesses_on_deposit_preauth_enabled'
  end
end
