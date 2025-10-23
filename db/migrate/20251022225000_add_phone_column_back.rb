# frozen_string_literal: true

class AddPhoneColumnBack < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:tenant_customers, :phone)
      add_column :tenant_customers, :phone, :string
    end
  end
end
