# frozen_string_literal: true

class CreateRentalBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :rental_bookings do |t|
      # Core associations
      t.references :business, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true  # The rental product
      t.references :product_variant, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :staff_member, foreign_key: true  # Who processed check-out/return
      t.references :location, foreign_key: true
      t.references :promotion, foreign_key: true
      
      # Timing (similar to bookings)
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.datetime :actual_pickup_time
      t.datetime :actual_return_time
      
      # Pricing
      t.string :rate_type  # hourly, daily, weekly
      t.decimal :rate_amount, precision: 10, scale: 2
      t.integer :rate_quantity  # Number of hours/days/weeks
      t.decimal :subtotal, precision: 10, scale: 2
      t.decimal :security_deposit_amount, precision: 10, scale: 2, default: 0
      t.decimal :tax_amount, precision: 10, scale: 2, default: 0
      t.decimal :discount_amount, precision: 10, scale: 2, default: 0
      t.decimal :total_amount, precision: 10, scale: 2
      t.decimal :late_fee_amount, precision: 10, scale: 2, default: 0
      t.decimal :damage_fee_amount, precision: 10, scale: 2, default: 0
      
      # Status workflow (similar to estimates for deposit flow)
      # pending_deposit -> deposit_paid -> checked_out -> returned -> completed
      # pending_deposit -> cancelled
      # checked_out -> overdue
      t.string :status, default: 'pending_deposit', null: false
      
      # Security deposit status
      t.string :deposit_status, default: 'pending', null: false
      t.decimal :deposit_refund_amount, precision: 10, scale: 2
      t.datetime :deposit_paid_at
      t.datetime :deposit_refunded_at
      
      # Quantity (for renting multiple of same item)
      t.integer :quantity, default: 1, null: false
      
      # Notes
      t.text :notes  # Internal notes
      t.text :customer_notes
      t.text :condition_notes_checkout
      t.text :condition_notes_return
      
      # Identifiers
      t.string :booking_number, null: false
      t.string :guest_access_token  # For guest access to booking details
      
      # Stripe payment tracking
      t.string :stripe_payment_intent_id
      t.string :stripe_deposit_payment_intent_id
      
      t.timestamps
    end

    add_index :rental_bookings, :booking_number, unique: true
    add_index :rental_bookings, :guest_access_token, unique: true
    add_index :rental_bookings, [:business_id, :status]
    add_index :rental_bookings, [:product_id, :start_time, :end_time]
    add_index :rental_bookings, [:tenant_customer_id, :status]
    add_index :rental_bookings, [:status, :end_time]  # For finding overdue rentals
  end
end

