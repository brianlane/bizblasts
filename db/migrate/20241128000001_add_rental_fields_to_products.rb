# frozen_string_literal: true

class AddRentalFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    # Add rental-specific fields to products table
    # Products with product_type: :rental will use these fields
    
    # Rental pricing (in addition to base price which becomes daily_rate for rentals)
    add_column :products, :hourly_rate, :decimal, precision: 10, scale: 2
    add_column :products, :weekly_rate, :decimal, precision: 10, scale: 2
    add_column :products, :security_deposit, :decimal, precision: 10, scale: 2, default: 0
    
    # Rental availability
    add_column :products, :rental_quantity_available, :integer, default: 1
    
    # Rental duration constraints (in minutes for consistency with booking system)
    add_column :products, :min_rental_duration_mins, :integer, default: 60  # 1 hour minimum
    add_column :products, :max_rental_duration_mins, :integer  # nil = no max
    
    # Rental type category
    add_column :products, :rental_category, :string, default: 'equipment'
    
    # Rental-specific options
    add_column :products, :rental_buffer_mins, :integer, default: 0  # Buffer between rentals
    add_column :products, :allow_hourly_rental, :boolean, default: true
    add_column :products, :allow_daily_rental, :boolean, default: true
    add_column :products, :allow_weekly_rental, :boolean, default: true
    
    # Location association for rentals
    add_reference :products, :location, foreign_key: true
    
    # Indexes
    add_index :products, [:business_id, :rental_category], where: "product_type = 3"  # rental type
  end
end

