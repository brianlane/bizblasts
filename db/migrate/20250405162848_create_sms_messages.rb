class CreateSmsMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :sms_messages do |t|
      t.references :marketing_campaign, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.string :phone_number, null: false
      t.text :content, null: false
      t.integer :status, default: 0, null: false
      t.datetime :sent_at
      t.datetime :delivered_at
      t.text :error_message

      t.timestamps
    end
    
    add_index :sms_messages, :status
  end
end
