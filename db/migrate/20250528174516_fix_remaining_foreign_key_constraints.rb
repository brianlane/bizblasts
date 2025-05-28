class FixRemainingForeignKeyConstraints < ActiveRecord::Migration[8.0]
  def up
    # Fix bookings -> staff_members constraint
    remove_foreign_key :bookings, :staff_members
    add_foreign_key :bookings, :staff_members, on_delete: :nullify
    
    # Fix bookings -> promotions constraint
    remove_foreign_key :bookings, :promotions
    add_foreign_key :bookings, :promotions, on_delete: :nullify
    
    # Fix tables that reference bookings
    remove_foreign_key :booking_product_add_ons, :bookings
    add_foreign_key :booking_product_add_ons, :bookings, on_delete: :cascade
    
    remove_foreign_key :invoices, :bookings
    add_foreign_key :invoices, :bookings, on_delete: :nullify
    
    remove_foreign_key :orders, :bookings
    add_foreign_key :orders, :bookings, on_delete: :nullify
    
    remove_foreign_key :promotion_redemptions, :bookings
    add_foreign_key :promotion_redemptions, :bookings, on_delete: :cascade
    
    remove_foreign_key :sms_messages, :bookings
    add_foreign_key :sms_messages, :bookings, on_delete: :cascade
    
    # Fix staff_members -> users constraint
    remove_foreign_key :staff_members, :users
    add_foreign_key :staff_members, :users, on_delete: :nullify
    
    # Fix services_staff_members constraints
    remove_foreign_key :services_staff_members, :staff_members
    add_foreign_key :services_staff_members, :staff_members, on_delete: :cascade
    
    remove_foreign_key :services_staff_members, :services
    add_foreign_key :services_staff_members, :services, on_delete: :cascade
    
    # Fix payments -> orders constraint (missing on_delete)
    remove_foreign_key :payments, :orders
    add_foreign_key :payments, :orders, on_delete: :nullify
    
    # Make nullable columns for nullify constraints
    change_column_null :bookings, :staff_member_id, true
    change_column_null :bookings, :promotion_id, true
    change_column_null :invoices, :booking_id, true
    change_column_null :orders, :booking_id, true
    change_column_null :staff_members, :user_id, true
    change_column_null :payments, :order_id, true
  end

  def down
    # Restore original constraints (this might fail if there are null values)
    
    # Restore bookings constraints
    remove_foreign_key :bookings, :staff_members
    add_foreign_key :bookings, :staff_members
    
    remove_foreign_key :bookings, :promotions
    add_foreign_key :bookings, :promotions
    
    # Restore tables that reference bookings
    remove_foreign_key :booking_product_add_ons, :bookings
    add_foreign_key :booking_product_add_ons, :bookings
    
    remove_foreign_key :invoices, :bookings
    add_foreign_key :invoices, :bookings
    
    remove_foreign_key :orders, :bookings
    add_foreign_key :orders, :bookings
    
    remove_foreign_key :promotion_redemptions, :bookings
    add_foreign_key :promotion_redemptions, :bookings
    
    remove_foreign_key :sms_messages, :bookings
    add_foreign_key :sms_messages, :bookings
    
    # Restore staff_members -> users constraint
    remove_foreign_key :staff_members, :users
    add_foreign_key :staff_members, :users
    
    # Restore services_staff_members constraints
    remove_foreign_key :services_staff_members, :staff_members
    add_foreign_key :services_staff_members, :staff_members
    
    remove_foreign_key :services_staff_members, :services
    add_foreign_key :services_staff_members, :services
    
    # Restore payments -> orders constraint
    remove_foreign_key :payments, :orders
    add_foreign_key :payments, :orders
    
    # Restore NOT NULL constraints (might fail)
    change_column_null :bookings, :staff_member_id, false
    change_column_null :bookings, :promotion_id, false
    change_column_null :invoices, :booking_id, false
    change_column_null :orders, :booking_id, false
    change_column_null :staff_members, :user_id, false
    change_column_null :payments, :order_id, false
  end
end
