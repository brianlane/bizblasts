class AddBookingToOrders < ActiveRecord::Migration[8.0]
  def change
    # Add booking reference to orders (index added by add_reference)
    add_reference :orders, :booking, null: true, foreign_key: true
    # Removed explicit add_index to avoid duplicate index
  end
end 