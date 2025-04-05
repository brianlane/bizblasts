class AddExternalIdToSmsMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :sms_messages, :external_id, :string
    add_index :sms_messages, :external_id
  end
end
