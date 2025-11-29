# frozen_string_literal: true

class AddRentalSettingsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    # Feature toggle
    add_column :businesses, :show_rentals_section, :boolean, default: false
    
    # Late fee settings
    add_column :businesses, :rental_late_fee_enabled, :boolean, default: true
    add_column :businesses, :rental_late_fee_percentage, :decimal, precision: 5, scale: 2, default: 15.0  # % of daily rate per day late
    
    # Buffer time between rentals (in minutes)
    add_column :businesses, :rental_buffer_mins, :integer, default: 30
    
    # Deposit settings
    add_column :businesses, :rental_require_deposit_upfront, :boolean, default: true
    
    # Notification settings
    add_column :businesses, :rental_reminder_hours_before, :integer, default: 24  # Send reminder X hours before return
  end
end

