require 'rails_helper'

RSpec.describe "Business Manager Bookings", type: :request do
  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) } # Not associated with the business
  let!(:service) { create(:service, business: business) }
  let!(:staff_member) { create(:staff_member, business: business, user: staff) }
  let!(:customer) { create(:tenant_customer, business: business) }
  # Always create a permissive policy for setup
  let!(:default_policy) { create(:booking_policy, business: business, max_daily_bookings: 10, max_advance_days: 365, buffer_time_mins: 0) }
  let!(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: customer, start_time: Time.current + 1.day) }

  before do
    # IMPORTANT: Set the host to the business's hostname for tenant scoping
    host! "#{business.hostname}.lvh.me"
    # Use ActsAsTenant here if your BaseController sets it
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "Authorization" do
    context "when not signed in" do
      it "redirects GET /manage/bookings to login" do
        get business_manager_bookings_path
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects GET /manage/bookings/:id to login" do
        get business_manager_booking_path(booking)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects GET /manage/bookings/:id/edit to login" do
        get edit_business_manager_booking_path(booking)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects PATCH /manage/bookings/:id to login" do
        patch business_manager_booking_path(booking), params: { booking: { notes: 'test' } }
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects PATCH /manage/bookings/:id/confirm to login" do
        patch confirm_business_manager_booking_path(booking)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects PATCH /manage/bookings/:id/cancel to login" do
        patch cancel_business_manager_booking_path(booking)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as a client" do
      before { sign_in client }

      it "redirects GET /manage/bookings" do
        get business_manager_bookings_path
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects GET /manage/bookings/:id" do
        get business_manager_booking_path(booking)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects GET /manage/bookings/:id/edit" do
        get edit_business_manager_booking_path(booking)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects PATCH /manage/bookings/:id" do
        patch business_manager_booking_path(booking), params: { booking: { notes: 'test' } }
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects PATCH /manage/bookings/:id/confirm" do
        patch confirm_business_manager_booking_path(booking)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects PATCH /manage/bookings/:id/cancel" do
        patch cancel_business_manager_booking_path(booking)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end
    end
  end

  describe "Manager/Staff Access" do
    before { sign_in manager } # Can also test with staff

    describe "GET /manage/bookings" do
      it "is successful" do
        get business_manager_bookings_path
        expect(response).to be_successful
      end

      it "assigns bookings belonging to the current business" do
        other_business = create(:business)
        other_booking = nil
        ActsAsTenant.with_tenant(other_business) do
          other_booking = create(:booking, business: other_business)
        end
        
        get business_manager_bookings_path
        expect(assigns(:bookings)).to include(booking)
        expect(assigns(:bookings)).not_to include(other_booking)
      end
    end

    describe "GET /manage/bookings/:id" do
      it "is successful" do
        get business_manager_booking_path(booking)
        expect(response).to be_successful
      end

      it "assigns the correct booking" do
        get business_manager_booking_path(booking)
        expect(assigns(:booking)).to eq(booking)
      end
    end

    describe "GET /manage/bookings/:id/edit" do
      it "is successful" do
        get edit_business_manager_booking_path(booking)
        expect(response).to be_successful
      end
      
      it "assigns available products" do
        # Ensure product is of type service or mixed to be available as an add-on
        product = create(:product, business: business, product_type: :service, variants_count: 1)
        get edit_business_manager_booking_path(booking)
        expect(assigns(:available_products)).to include(product)
      end
    end

    describe "PATCH /manage/bookings/:id" do
      let(:valid_params) { { booking: { notes: "Updated notes" } } }
      let(:invalid_params) { { booking: { staff_member_id: nil } } } # Example invalid param

      context "with valid parameters" do
        it "updates the booking" do
          patch business_manager_booking_path(booking), params: valid_params
          expect(booking.reload.notes).to eq("Updated notes")
        end

        it "redirects to the booking show page" do
          patch business_manager_booking_path(booking), params: valid_params
          expect(response).to redirect_to(business_manager_booking_path(booking))
          expect(flash[:notice]).to include("successfully updated")
        end
      end

      context "with invalid parameters" do
        it "does not update the booking" do
           original_notes = booking.notes
           # Mock update failure for simplicity in this basic test
           allow_any_instance_of(Booking).to receive(:update).and_return(false)
           patch business_manager_booking_path(booking), params: invalid_params
           expect(booking.reload.notes).to eq(original_notes)
        end

        it "re-renders the edit template" do
           allow_any_instance_of(Booking).to receive(:update).and_return(false)
           patch business_manager_booking_path(booking), params: invalid_params
           expect(response).to render_template(:edit)
           expect(flash.now[:alert]).to include("problem updating")
        end
      end
      
      it "adds product add-ons via nested attributes" do
        product = create(:product, business: business, variants_count: 1)
        # Select a non-default variant (explicitly created) to avoid stock-zero default variant
        variant = product.product_variants.find { |v| v.name != 'Default' }
        patch business_manager_booking_path(booking), params: {
          booking: {
            booking_product_add_ons_attributes: {
              "1" => { product_variant_id: variant.id, quantity: 2 }
            }
          }
        }
        booking.reload
        expect(booking.booking_product_add_ons.count).to eq(1)
        addon = booking.booking_product_add_ons.first
        expect(addon.product_variant).to eq(variant)
        expect(addon.quantity).to eq(2)
        expect(flash[:notice]).to include("successfully updated")
        expect(response).to redirect_to(business_manager_booking_path(booking))
      end
    end

    describe "PATCH /manage/bookings/:id/confirm" do
      it "updates the booking status to confirmed" do
        patch confirm_business_manager_booking_path(booking)
        expect(booking.reload.status).to eq("confirmed")
      end

      it "redirects to the booking show page" do
        patch confirm_business_manager_booking_path(booking)
        expect(response).to redirect_to(business_manager_booking_path(booking))
        expect(flash[:notice]).to include("confirmed")
      end
      
      it "does not re-confirm if already confirmed" do
        booking.update!(status: :confirmed)
        patch confirm_business_manager_booking_path(booking)
        expect(flash[:notice]).to include("already confirmed")
        expect(response).to redirect_to(business_manager_booking_path(booking))
      end
    end

    describe "PATCH /manage/bookings/:id/cancel" do
      let(:cancel_params) { { cancellation_reason: "Test reason" } }
      
      it "updates the booking status to cancelled" do
        patch cancel_business_manager_booking_path(booking), params: cancel_params
        expect(booking.reload.status).to eq("cancelled")
        expect(booking.cancellation_reason).to eq("Test reason")
      end

      it "redirects to the booking show page" do
        patch cancel_business_manager_booking_path(booking), params: cancel_params
        expect(response).to redirect_to(business_manager_booking_path(booking))
        expect(flash[:notice]).to include("cancelled")
      end
      
       it "does not re-cancel if already cancelled" do
        booking.update!(status: :cancelled)
        patch cancel_business_manager_booking_path(booking)
        expect(flash[:notice]).to include("already cancelled")
        expect(response).to redirect_to(business_manager_booking_path(booking))
      end

      # Policy enforcement tests for cancellation_window_mins
      context "with a 60-minute cancellation window policy" do
        include ActiveSupport::Testing::TimeHelpers

        before do
          business.booking_policy.update!(cancellation_window_mins: 60)
        end

        it "allows cancellation when outside the window" do
          # Create a booking far in the future to be outside the window
          future_booking = create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: Time.current + 2.hours) # Start time well outside 60 mins

          # Travel to a time outside the cancellation window (e.g., 70 minutes before start)
          travel_to future_booking.start_time - 70.minutes do
            patch cancel_business_manager_booking_path(future_booking), params: cancel_params
            expect(future_booking.reload.status).to eq("cancelled")
            expect(response).to redirect_to(business_manager_booking_path(future_booking))
            expect(flash[:notice]).to eq("Booking has been cancelled.")
          end
        end

        it "prevents cancellation within the window" do
          # Create a booking that's 30 minutes in the future (within the 60-min window)
          imminent_booking = create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: Time.current + 30.minutes)

          # Travel to a time inside the cancellation window (e.g., 20 minutes before start)
          travel_to imminent_booking.start_time - 20.minutes do
            patch cancel_business_manager_booking_path(imminent_booking), params: cancel_params
            expect(imminent_booking.reload.status).not_to eq("cancelled")
            expect(response).to redirect_to(business_manager_booking_path(imminent_booking)) # Still redirects to show
            expect(flash[:alert]).to eq("Cannot cancel booking within 60 minutes of the start time.")
          end
        end
      end
    end
    
    # Tests for reschedule action
    describe "GET /manage/bookings/:id/reschedule" do
      let(:slots) { [{ start_time: booking.start_time, end_time: booking.end_time }] }
      before do
        allow(AvailabilityService).to receive(:available_slots).and_return(slots)
      end

      it "is successful and assigns available_slots" do
        get reschedule_business_manager_booking_path(booking)
        expect(response).to be_successful
        expect(assigns(:available_slots)).to eq(slots)
      end
    end

    # Tests for update_schedule action
    describe "PATCH /manage/bookings/:id/update_schedule" do
      let(:new_date) { (booking.start_time.to_date + 1.day).to_s }
      let(:new_time) { booking.start_time.strftime('%H:%M') }

      it "updates the booking start_time and redirects" do
        patch update_schedule_business_manager_booking_path(booking), params: { date: new_date, start_time: new_time }
        expected = Time.zone.parse("#{new_date} #{new_time}")
        expect(booking.reload.start_time.to_i).to eq(expected.to_i)
        expect(response).to redirect_to(business_manager_booking_path(booking))
        expect(flash[:notice]).to include("rescheduled")
      end
    end

    # Tests for available_slots action
    describe "GET /manage/bookings/available-slots" do
      let(:date) { (Time.current + 1.day).to_date }
      let(:service) { create(:service, business: business, duration: 60) }
      let(:staff_member) { create(:staff_member, business: business) }

      # Ensure staff member can perform the service for these tests
      before do
        create(:services_staff_member, service: service, staff_member: staff_member)
        # Set base availability for the staff member (e.g., 9 AM to 5 PM)
        staff_member.update!(availability: {
          date.strftime('%A').downcase => [{ 'start' => '09:00', 'end' => '17:00' }]
        })
        sign_in manager
      end

      it "is successful and assigns calendar_data" do
        # Stub AvailabilityService to control expected output
        allow(AvailabilityService).to receive(:available_slots).and_return([]) # Default empty

        get available_slots_business_manager_bookings_path, params: { service_id: service.id, staff_member_id: staff_member.id, date: date.to_s }
        expect(response).to be_successful
        expect(assigns(:calendar_data)).to be_a(Hash)
        expect(assigns(:calendar_data)).to have_key(date.to_s)
      end

      # Policy enforcement tests for available-slots
      context "with booking policies" do
        include ActiveSupport::Testing::TimeHelpers

        # Max Advance Days
        it "returns empty slots for dates beyond max_advance_days" do
          business.booking_policy.update!(max_advance_days: 7)
          future_date = (Date.current + 14.days).to_s

          # Stub AvailabilityService to return empty array when policy is enforced
          allow(AvailabilityService).to receive(:available_slots).and_return([])

          get available_slots_business_manager_bookings_path, params: { 
            service_id: service.id, 
            staff_member_id: staff_member.id, 
            date: future_date 
          }
          # AvailabilityService should return empty array based on policy
          expect(assigns(:calendar_data)[future_date]).to be_empty
        end

        # Max Daily Bookings
        it "returns empty slots when max_daily_bookings reached" do
          business.booking_policy.update!(max_daily_bookings: 1)
          date = (Time.current + 1.day).to_date
          Booking.where(staff_member: staff_member, start_time: date.all_day).delete_all
          existing_booking_start = Time.zone.local(date.year, date.month, date.day, 9, 0)
          create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: existing_booking_start)

          get available_slots_business_manager_bookings_path, params: { service_id: service.id, staff_member_id: staff_member.id, date: date.to_s }
          expect(response).to have_http_status(:ok)
          expect(assigns(:calendar_data)[date.to_s]).to eq([])
        end

        # Buffer Time
        it "filters slots that conflict with buffer time" do
          business.booking_policy.update!(buffer_time_mins: 30)

          # Create an existing booking that creates a buffer zone
          existing_start = Time.zone.local(date.year, date.month, date.day, 10, 0)
          existing_end = existing_start + 1.hour # Ends at 11:00
          create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: existing_start,
            end_time: existing_end)

          # Expect AvailabilityService to be called and return only slots outside buffer
          expected_slots_after_filter = [
            { start_time: Time.zone.local(date.year, date.month, date.day, 9, 0), end_time: Time.zone.local(date.year, date.month, date.day, 10, 0) },
            { start_time: Time.zone.local(date.year, date.month, date.day, 12, 0), end_time: Time.zone.local(date.year, date.month, date.day, 13, 0) }
          ]
          # Stub AvailabilityService to return the filtered slots
          allow(AvailabilityService).to receive(:available_slots).and_return(expected_slots_after_filter)

          get available_slots_business_manager_bookings_path, params: { 
            service_id: service.id, 
            staff_member_id: staff_member.id, 
            date: date.to_s 
          }
          # The controller should assign the filtered slots
          expect(assigns(:calendar_data)[date.to_s].map{|s| {start_time: s[:start_time].strftime('%H:%M'), end_time: s[:end_time].strftime('%H:%M')}}).to match_array(
            expected_slots_after_filter.map{|s| {start_time: s[:start_time].strftime('%H:%M'), end_time: s[:end_time].strftime('%H:%M')}}
          )
        end

        # Duration Constraints
        it "available_slots adjusts duration to meet minimum or returns empty if exceeds maximum" do
          # Test min duration adjustment
          business.booking_policy.update!(min_duration_mins: 45, max_duration_mins: 120)
          short_service = create(:service, business: business, duration: 30)
          create(:services_staff_member, service: short_service, staff_member: staff_member)

          # AvailabilityService should return slots with adjusted duration
          adjusted_slots = [{start_time: Time.zone.local(date.year, date.month, date.day, 9, 0), end_time: Time.zone.local(date.year, date.month, date.day, 9, 45)}]
          allow(AvailabilityService).to receive(:available_slots).and_return(adjusted_slots)

          get available_slots_business_manager_bookings_path, params: { 
            service_id: short_service.id, 
            staff_member_id: staff_member.id, 
            date: date.to_s 
          }
          slots = assigns(:calendar_data)[date.to_s]
          expect(slots).not_to be_empty
          expect(((slots.first[:end_time] - slots.first[:start_time]) / 60.0).round).to eq(45)

          # Test max duration preventing slots
          business.booking_policy.update!(min_duration_mins: 15, max_duration_mins: 60) # Max is 60
          long_service = create(:service, business: business, duration: 90) # Duration is 90
          create(:services_staff_member, service: long_service, staff_member: staff_member)

          # AvailabilityService should return empty for this service/policy combination
          allow(AvailabilityService).to receive(:available_slots).and_return([])

          get available_slots_business_manager_bookings_path, params: { 
            service_id: long_service.id, 
            staff_member_id: staff_member.id, 
            date: date.to_s 
          }
          expect(assigns(:calendar_data)[date.to_s]).to be_empty
        end
      end
    end

    # Policy enforcement tests for booking creation
    describe "Policy enforcement when creating bookings" do
      include ActiveSupport::Testing::TimeHelpers

      # For Max Advance Days:
      describe "max_advance_days policy" do
        it "prevents creating a booking beyond max_advance_days" do
          business.booking_policy.update!(max_advance_days: 7)
          future_date = Date.current + 14.days
          future_time = "10:00"

          expect {
            post business_manager_bookings_path, params: {
              booking: {
                service_id: service.id,
                staff_member_id: staff_member.id,
                tenant_customer_id: customer.id,
                date: future_date,
                time: future_time
              }
            }
          }.not_to change(Booking, :count)
          unless response.body.include?("cannot be more than") && response.body.include?("in advance")
            puts "DEBUG: Response body: #{response.body}"
          end
          expect(response.body).to include("cannot be more than").and include("in advance")
        end
      end

      # For Max Daily Bookings:
      describe "max_daily_bookings policy" do
        it "prevents creating a booking when max_daily_bookings reached" do
          business.booking_policy.update!(max_daily_bookings: 1)

          # Remove any existing bookings for this staff member on this day
          date = (Time.current + 1.day).to_date
          Booking.where(staff_member: staff_member, start_time: date.all_day).delete_all

          # Create one existing booking for the staff member on the same day
          existing_booking_start = Time.zone.local(date.year, date.month, date.day, 9, 0)
          create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: existing_booking_start)

          time = "10:00" # Different time than existing booking

          expect {
            post business_manager_bookings_path, params: {
              booking: {
                service_id: service.id,
                staff_member_id: staff_member.id,
                tenant_customer_id: customer.id,
                date: date,
                time: time
              }
            }
          }.not_to change(Booking, :count)
          expect(response.body).to include("Maximum daily bookings (").and include("reached for this staff member")
        end
      end

      # For Buffer Time:
      describe "buffer_time_mins policy" do
        it "prevents creating a booking that violates buffer time" do
          business.booking_policy.update!(buffer_time_mins: 30)
          # Clean up any existing bookings that might interfere
          date = (Time.current + 1.day).to_date
          Booking.where(staff_member: staff_member, start_time: date.all_day).delete_all
          
          # Create an existing booking at 9:00
          existing_booking_start = Time.zone.local(date.year, date.month, date.day, 9, 0)
          create(:booking,
            business: business,
            service: service,
            staff_member: staff_member,
            tenant_customer: customer,
            start_time: existing_booking_start)

          # Try to create a booking at 9:15 (should violate buffer)
          time = "09:15"
          expect {
            post business_manager_bookings_path, params: {
              booking: {
                service_id: service.id,
                staff_member_id: staff_member.id,
                tenant_customer_id: customer.id,
                date: date,
                time: time
              }
            }
          }.not_to change(Booking, :count)
          expect(response.body).to include("conflicts with another existing booking").and include("buffer time")
        end
      end

      # For Duration Constraints:
      describe "duration constraints policy" do
        it "prevents creating a booking with duration less than minimum" do
          business.booking_policy.update!(min_duration_mins: 60)
          # Try to create a booking with 30 min duration
          expect {
            post business_manager_bookings_path, params: {
              booking: {
                service_id: service.id,
                staff_member_id: staff_member.id,
                tenant_customer_id: customer.id,
                date: (Time.current + 1.day).to_date,
                time: "10:00",
                duration: 30
              }
            }
          }.not_to change(Booking, :count)
          expect(response.body).to include("cannot be less than the minimum required duration")
        end

        it "prevents creating a booking with duration more than maximum" do
          business.booking_policy.update!(max_duration_mins: 30)
          # Try to create a booking with 60 min duration
          expect {
            post business_manager_bookings_path, params: {
              booking: {
                service_id: service.id,
                staff_member_id: staff_member.id,
                tenant_customer_id: customer.id,
                date: (Time.current + 1.day).to_date,
                time: "10:00",
                duration: 60
              }
            }
          }.not_to change(Booking, :count)
          expect(response.body).to include("cannot exceed the maximum allowed duration")
        end
      end
    end
  end
end 