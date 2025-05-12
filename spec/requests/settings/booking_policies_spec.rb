# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Settings::BookingPolicies", type: :request do
  let(:business) { FactoryBot.create(:business) }
  let(:manager_user) { FactoryBot.create(:user, :manager, business: business) } # Assuming a :manager trait or similar
  let(:staff_user) { FactoryBot.create(:user, :staff, business: business) }     # Assuming a :staff trait
  let!(:booking_policy) { FactoryBot.create(:booking_policy, business: business) }

  before do
    # Mock current_business. This might be handled by a helper or directly in tests.
    # For this example, let's assume a way to set current_business for the request context.
    # If using a SubdomainConstraint, ensure the host is set appropriately.
    # allow_any_instance_of(ApplicationController).to receive(:current_business).and_return(business)
    # Note: The above ApplicationController stub might be too broad. Prefer controller-specific stubs or helpers.
    # For BusinessManager controllers, it might be:
    allow_any_instance_of(Settings::BookingPoliciesController).to receive(:current_business).and_return(business)
  end

  describe "GET /manage/settings/booking_policy" do # show
    context "when logged in as a manager" do
      before { sign_in manager_user }

      it "succeeds" do
        get settings_booking_policy_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do # Or redirects, depending on Pundit setup
        get settings_booking_policy_path
        expect(response).to have_http_status(:forbidden) # Or :redirect, or check flash message
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get settings_booking_policy_path
        expect(response).to redirect_to(new_user_session_path) # Or appropriate login path
      end
    end
  end

  describe "GET /manage/settings/booking_policy/edit" do
    context "when logged in as a manager" do
      before { sign_in manager_user }

      it "succeeds" do
        get edit_settings_booking_policy_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do
        get edit_settings_booking_policy_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /manage/settings/booking_policy" do # update
    let(:valid_attributes) do
      { cancellation_window_mins: 60, buffer_time_mins: 15, max_daily_bookings: 10, max_advance_days: 30, intake_fields: '[{"name":"test"}]' }
    end
    let(:invalid_attributes) do
      { cancellation_window_mins: -10 } # Example of invalid data based on model validation
    end

    context "when logged in as a manager" do
      before { sign_in manager_user }

      context "with valid parameters" do
        it "updates the booking policy and redirects" do
          patch settings_booking_policy_path, params: { booking_policy: valid_attributes }
          booking_policy.reload
          expect(booking_policy.cancellation_window_mins).to eq(60)
          expect(booking_policy.intake_fields).to eq([{ "name" => "test" }]) # Assuming model parses JSON string
          expect(response).to redirect_to(settings_booking_policy_path)
          expect(flash[:notice]).to eq('Booking policies updated successfully.')
        end
      end

      context "with invalid parameters" do
        it "does not update the booking policy and re-renders edit" do
          patch settings_booking_policy_path, params: { booking_policy: invalid_attributes }
          booking_policy.reload
          expect(booking_policy.cancellation_window_mins).not_to eq(-10)
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:edit)
        end
      end
    end

    context "when logged in as staff (non-manager)" do
      before { sign_in staff_user }

      it "is forbidden" do
        patch settings_booking_policy_path, params: { booking_policy: valid_attributes }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end 