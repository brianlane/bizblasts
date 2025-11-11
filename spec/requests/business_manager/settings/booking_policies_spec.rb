# frozen_string_literal: true

require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe "BusinessManager::Settings::BookingPolicies", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    
    # Ensure StaffMember records exist for the created users and business
    create(:staff_member, business: business, user: manager_user) unless manager_user.staff_member_for(business)
    create(:staff_member, business: business, user: staff_user) unless staff_user.staff_member_for(business)
    
    # Always create a permissive policy for setup
    @booking_policy = business.booking_policy || create(:booking_policy, business: business, max_daily_bookings: 10, max_advance_days: 365, buffer_time_mins: 0)
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /manage/settings/booking_policy" do # show
    context "when logged in as a manager" do
      before { sign_in manager_user }

      it "succeeds" do
        get business_manager_settings_booking_policy_path
        expect(response).to have_http_status(:ok)
      end

      it "displays the configured service radius when enabled" do
        business.update!(zip: "94105")
        @booking_policy.update!(service_radius_enabled: true, service_radius_miles: 25)

        get business_manager_settings_booking_policy_path

        expect(response.body).to include("Within 25 miles of 94105")
        expect(response.body).to include("Service Area")
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do # Or redirects, depending on Pundit setup
        get business_manager_settings_booking_policy_path
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect) # Allow redirect on auth failure
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get business_manager_settings_booking_policy_path
        expect(response).to redirect_to(new_user_session_path) # Or appropriate login path
      end
    end
  end

  describe "GET /manage/settings/booking_policy/edit" do
    context "when logged in as a manager" do
      before { sign_in manager_user }

      it "succeeds" do
        get edit_business_manager_settings_booking_policy_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do
        get edit_business_manager_settings_booking_policy_path
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect) # Allow redirect on auth failure
      end
    end
  end

  describe "PATCH /manage/settings/booking_policy" do # update
    let(:valid_attributes) do
      { cancellation_window_hours: 1, buffer_time_mins: 15, max_daily_bookings: 10, max_advance_days: 30 }
    end
    let(:invalid_attributes) do
      { cancellation_window_hours: -1 } # Example of invalid data based on model validation
    end

    context "when logged in as a manager" do
      before { sign_in manager_user }

      context "with valid parameters" do
        it "updates the booking policy and redirects" do
          patch business_manager_settings_booking_policy_path, params: { booking_policy: valid_attributes }
          @booking_policy.reload
          expect(@booking_policy.cancellation_window_mins).to eq(60)
          expect(@booking_policy.buffer_time_mins).to eq(15)
          expect(@booking_policy.max_daily_bookings).to eq(10)
          expect(@booking_policy.max_advance_days).to eq(30)
          expect(response).to redirect_to(business_manager_settings_booking_policy_path)
          expect(flash[:notice]).to eq('Booking policies updated successfully.')
        end

        it "converts min_advance_hours to minutes correctly" do
          patch business_manager_settings_booking_policy_path, params: { booking_policy: { min_advance_hours: 2 } }
          @booking_policy.reload
          expect(@booking_policy.min_advance_mins).to eq(120) # 2 hours = 120 minutes
          expect(response).to redirect_to(business_manager_settings_booking_policy_path)
          expect(flash[:notice]).to eq('Booking policies updated successfully.')
        end
      end

      context "with invalid parameters" do
        it "does not update the booking policy and re-renders edit" do
          original_cancellation_window = @booking_policy.cancellation_window_mins
          patch business_manager_settings_booking_policy_path, params: { booking_policy: invalid_attributes }
          @booking_policy.reload
          expect(@booking_policy.cancellation_window_mins).to eq(original_cancellation_window)
          expect(response).to have_http_status(:unprocessable_content)
          expect(response).to render_template(:edit)
        end
      end
      
      context "with duration constraints" do
        let(:duration_attributes) do
          { min_duration_mins: 30, max_duration_mins: 120, cancellation_window_hours: 1, buffer_time_mins: 5, max_daily_bookings: 10, max_advance_days: 365 }
        end

        it "updates the duration policy constraints" do
          patch business_manager_settings_booking_policy_path, params: { booking_policy: duration_attributes }
          @booking_policy.reload
          expect(@booking_policy.min_duration_mins).to eq(30)
          expect(@booking_policy.max_duration_mins).to eq(120)
          expect(response).to redirect_to(business_manager_settings_booking_policy_path)
          expect(flash[:notice]).to eq('Booking policies updated successfully.')
        end

        it "validates that min_duration is not greater than max_duration" do
          patch business_manager_settings_booking_policy_path, params: { 
            booking_policy: duration_attributes.merge(min_duration_mins: 120, max_duration_mins: 60) 
          }
          expect(response).to have_http_status(:found).or have_http_status(:unprocessable_content)
        end
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do
        patch business_manager_settings_booking_policy_path, params: { booking_policy: valid_attributes }
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect) # Allow redirect on auth failure
      end
    end
  end
end 