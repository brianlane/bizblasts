require 'rails_helper'

RSpec.describe "Client::Bookings", type: :request do
  let!(:business) { create(:business) }
  let!(:client) { create(:user, :client) }
  let!(:service) { create(:service, business: business) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: client.email) }
  # Always create a permissive policy for setup
  let!(:default_policy) { create(:booking_policy, business: business, max_daily_bookings: 10, max_advance_days: 365, buffer_time_mins: 0) }
  let!(:booking) do 
    create(:booking, 
      business: business, 
      service: service, 
      staff_member: staff_member, 
      tenant_customer: tenant_customer,
      start_time: Time.current + 1.day,
      status: :confirmed)
  end

  before do
    # Set the tenant for the test
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in client
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "Authorization" do
    it "allows access to client bookings index" do
      get client_bookings_path
      expect(response).to be_successful
    end

    it "allows access to client booking show" do
      get client_booking_path(booking) # Use the created booking
      expect(response).to be_successful
    end
    
    # Add more authorization tests as needed for edit/update
  end

  describe "PATCH /client/bookings/:id/cancel with cancellation_window_mins" do
    context "with a 60-minute cancellation window policy" do
      include ActiveSupport::Testing::TimeHelpers

      before do
        business.booking_policy.update!(cancellation_window_mins: 60)
        # Ensure the existing booking used in tests is confirmed and in the future
        booking.update!(start_time: Time.current + 1.day, status: :confirmed)
      end

      it "allows cancellation when outside the window" do
        cancellable_booking = create(:booking,
          business: business,
          service: service,
          staff_member: staff_member,
          tenant_customer: tenant_customer,
          start_time: Time.current + 2.hours, # Start time well outside 60 mins
          status: :confirmed
        )
        # Travel to a time outside the cancellation window (e.g., 70 minutes before start)
        travel_to cancellable_booking.start_time - 70.minutes do
          patch cancel_client_booking_path(cancellable_booking)
          unless cancellable_booking.reload.status == "cancelled"
            puts "DEBUG: Response body: #{response.body}"
            puts "DEBUG: Flash: #{flash.inspect}"
          end
          expect(cancellable_booking.reload.status).to eq("cancelled")
          expect(response).to redirect_to(client_booking_path(cancellable_booking))
          expect(flash[:notice]).to eq("Your booking has been successfully cancelled.")
        end
      end

      it "prevents cancellation within the window" do
        imminent_booking = create(:booking,
          business: business,
          service: service,
          staff_member: staff_member,
          tenant_customer: tenant_customer,
          start_time: Time.current + 30.minutes,
          status: :confirmed)
        # Travel to a time inside the cancellation window (e.g., 20 minutes before start)
        travel_to imminent_booking.start_time - 20.minutes do
          patch cancel_client_booking_path(imminent_booking)
          if imminent_booking.reload.status == "cancelled"
            puts "DEBUG: Response body: #{response.body}"
            puts "DEBUG: Flash: #{flash.inspect}"
          end
          expect(imminent_booking.reload.status).not_to eq("cancelled")
          expect(response).to redirect_to(client_booking_path(imminent_booking))
          expect(flash[:alert]).to eq("Unable to cancel this booking. Please try again.")
        end
      end
    end
  end
end 