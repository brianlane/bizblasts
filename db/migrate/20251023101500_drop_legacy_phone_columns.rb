# frozen_string_literal: true

class DropLegacyPhoneColumns < ActiveRecord::Migration[8.0]
  def change
    # Once data verified encrypted, remove clear-text columns
    remove_column :tenant_customers, :phone, :string
    remove_column :sms_messages,   :phone_number, :string
  end
end
