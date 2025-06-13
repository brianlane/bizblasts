class AddPromoCodeFieldsToBookingsAndOrders < ActiveRecord::Migration[8.0]
  def change
    # Add promo code fields to bookings
    add_column :bookings, :applied_promo_code, :string
    add_column :bookings, :promo_discount_amount, :decimal, precision: 10, scale: 2
    add_column :bookings, :promo_code_type, :string
    
    # Add promo code fields to orders  
    add_column :orders, :applied_promo_code, :string
    add_column :orders, :promo_discount_amount, :decimal, precision: 10, scale: 2
    add_column :orders, :promo_code_type, :string
    
    # Add indexes for performance
    add_index :bookings, :applied_promo_code
    add_index :bookings, :promo_code_type
    add_index :orders, :applied_promo_code
    add_index :orders, :promo_code_type
  end
end
