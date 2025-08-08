class AddReviewRequestSuppressedToInvoicesOrdersBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :review_request_suppressed, :boolean, default: false, null: false
    add_column :orders, :review_request_suppressed, :boolean, default: false, null: false  
    add_column :bookings, :review_request_suppressed, :boolean, default: false, null: false
  end
end
