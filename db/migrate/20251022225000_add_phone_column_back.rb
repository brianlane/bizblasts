# frozen_string_literal: true

class AddPhoneColumnBack < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:tenant_customers, :phone)
      add_column :tenant_customers, :phone, :string
    end

    unless column_exists?(:sms_messages, :phone_number)
      add_column :sms_messages, :phone_number, :string
    end
  end
end
