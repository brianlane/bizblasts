require 'rails_helper'

RSpec.describe "Business Manager Bookings", type: :request do
  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) } # Not associated with the business
  let!(:service) { create(:service, business: business) }
  let!(:staff_member) { create(:staff_member, business: business, user: staff) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: customer) }

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
         product = create(:product, business: business, variants_count: 1)
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
        variant = product.product_variants.first
        patch business_manager_booking_path(booking), params: {
          booking: {
            booking_product_add_ons_attributes: {
              "0" => { product_variant_id: variant.id, quantity: 2 }
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
      let(:date) { booking.start_time.to_date }
      let(:slots) { [{ start_time: booking.start_time, end_time: booking.end_time }] }
      before do
        allow(AvailabilityService).to receive(:available_slots).and_return(slots)
      end

      it "is successful and assigns calendar_data" do
        get available_slots_business_manager_bookings_path, params: { service_id: service.id, staff_member_id: staff_member.id, date: date.to_s }
        expect(response).to be_successful
        expect(assigns(:calendar_data)).to be_a(Hash)
        expect(assigns(:calendar_data)[date.to_s]).to eq(slots)
      end
    end
  end
end 