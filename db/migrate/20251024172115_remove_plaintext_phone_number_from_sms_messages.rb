# frozen_string_literal: true

class RemovePlaintextPhoneNumberFromSmsMessages < ActiveRecord::Migration[8.0]
  def up
    remove_column :sms_messages, :phone_number
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore plaintext sms_messages.phone_number once removed"
  end
end
