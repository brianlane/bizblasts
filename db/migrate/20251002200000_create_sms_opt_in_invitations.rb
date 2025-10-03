class CreateSmsOptInInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_opt_in_invitations do |t|
      t.string :phone_number, null: false
      t.references :business, null: false, foreign_key: true
      t.references :tenant_customer, null: true, foreign_key: true
      t.string :context, null: false # booking_confirmation, booking_reminder, order_update, etc.
      t.datetime :sent_at, null: false
      t.datetime :responded_at, null: true
      t.string :response, null: true # YES, NO, STOP, etc.
      t.boolean :successful_opt_in, default: false, null: false

      t.timestamps
    end

    # Index for fast lookups by phone and business
    add_index :sms_opt_in_invitations, [:phone_number, :business_id]

    # Index for finding recent invitations (30-day rule)
    add_index :sms_opt_in_invitations, [:phone_number, :business_id, :sent_at]

    # Index for analytics queries
    add_index :sms_opt_in_invitations, :sent_at
    add_index :sms_opt_in_invitations, :responded_at
    add_index :sms_opt_in_invitations, :successful_opt_in
  end
end