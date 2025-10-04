class CreatePendingSmsNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :pending_sms_notifications do |t|
      # Required references
      t.references :business, null: false, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true

      # Optional references for specific notification types
      t.references :booking, null: true, foreign_key: true
      t.references :invoice, null: true, foreign_key: true
      t.references :order, null: true, foreign_key: true

      # Notification details
      t.string :notification_type, null: false # 'booking_confirmation', 'invoice_created', etc.
      t.string :sms_type, null: false # 'booking', 'payment', 'order', etc.
      t.json :template_data, null: false # Variables for SMS template rendering
      t.text :phone_number, null: false # Store phone number for safety

      # Lifecycle tracking
      t.datetime :queued_at, null: false
      t.datetime :expires_at, null: false # Auto-expire old notifications (7 days)
      t.datetime :processed_at, null: true # When the notification was sent/processed
      t.datetime :failed_at, null: true # If processing failed
      t.text :failure_reason, null: true # Why processing failed

      # Status tracking
      t.string :status, default: 'pending' # 'pending', 'sent', 'failed', 'expired'

      # Prevent duplicates
      t.string :deduplication_key, null: false # Unique key to prevent duplicate queuing

      t.timestamps
    end

    # Indexes for performance
    add_index :pending_sms_notifications, [:business_id, :tenant_customer_id]
    add_index :pending_sms_notifications, [:status, :queued_at]
    add_index :pending_sms_notifications, [:expires_at]
    add_index :pending_sms_notifications, [:deduplication_key], unique: true
    add_index :pending_sms_notifications, [:notification_type]
    add_index :pending_sms_notifications, [:phone_number]
  end
end
