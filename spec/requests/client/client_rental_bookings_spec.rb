require 'rails_helper'

RSpec.describe "Client::RentalBookings", type: :request do
  let!(:business) { create(:business) }
  let!(:client) { create(:user, :client) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: client.email) }
  let!(:rental_product) { create(:product, :rental, business: business, rental_quantity_available: 3, price: 50) }
  let!(:rental_booking) do
    create(:rental_booking,
           business: business,
           product: rental_product,
           tenant_customer: tenant_customer,
           start_time: 2.days.from_now,
           end_time: 3.days.from_now)
  end

  before do
    # Client rental bookings is a main domain route for cross-business view
    host! "www.example.com"
    sign_in client
  end

  describe "GET /my-rentals" do
    it "allows access to client rental bookings index" do
      get client_rental_bookings_path
      expect(response).to be_successful
      expect(response.body).to include("My Rentals")
      expect(response.body).to include(rental_booking.rental_name)
    end
  end

  describe "GET /my-rentals/:id" do
    it "allows access to a specific rental booking" do
      get client_rental_booking_path(rental_booking)
      expect(response).to be_successful
      expect(response.body).to include(rental_booking.booking_number)
    end
  end
end

