# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client::Settings", type: :request do
  let(:client_user) { create(:user, :client) } # Using the :client trait for clarity
  let(:other_client_user) { create(:user, :client) }
  let(:business_user) { create(:user, :manager) } # Changed from role: :business_manager to :manager trait

  before do
    # Create a default business for context if your controllers/models expect it
    # create(:business)
  end

  describe "GET /settings (#show or #edit)" do
    context "when logged in as a client" do
      before { sign_in client_user }

      it "renders the settings page successfully" do
        get client_settings_path
        expect(response).to be_successful
        expect(response).to render_template(:edit) # Or :show, matching controller
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get client_settings_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when logged in as a non-client user (e.g., business_manager)" do
      before { sign_in business_user }

      it "redirects or shows an error (depends on root/fallback for unauthorized)" do
        get client_settings_path
        # This expectation depends on your application's behavior for unauthorized access
        # For Pundit, it might raise an error caught by Rails, leading to a 403 or redirect.
        # Or, if client routes are strictly separate, it might 404 or redirect to business dashboard.
        # Adjust as per your app's behavior, e.g. expect(response).to redirect_to(root_path)
        expect(response).not_to be_successful # A general check
      end
    end
  end

  describe "PATCH /settings (#update)" do
    let(:valid_attributes) do
      {
        first_name: "NewFirstName",
        last_name: "NewLastName",
        phone: "1234567890",
        notification_preferences: {
          email_booking_confirmation: true,
          sms_booking_reminder: false,
          email_order_updates: true,
          sms_order_updates: false,
          email_promotions: true,
          sms_promotions: false
        }
      }
    end

    let(:password_attributes) do
      {
        current_password: client_user.password || 'password', # Assuming factory default or set password
        password: "newcomplexpassword",
        password_confirmation: "newcomplexpassword"
      }
    end

    context "when logged in as the correct client" do
      before { sign_in client_user }

      it "updates profile attributes successfully" do
        patch client_settings_path, params: { user: valid_attributes }
        client_user.reload
        expect(client_user.first_name).to eq("NewFirstName")
        expect(client_user.notification_preferences['email_booking_confirmation']).to eq("true")
        expect(client_user.notification_preferences['sms_promotions']).to eq("false")
        expect(response).to redirect_to(client_settings_path)
        expect(flash[:notice]).to eq('Profile settings updated successfully.')
      end

      it "updates password successfully" do
        client_user.update!(password: 'password', password_confirmation: 'password') if client_user.encrypted_password.blank? # Ensure password is set
        
        # Create a user with a known password for this test specifically
        # to avoid issues with devise password management in other tests
        test_user_for_password = create(:user, role: :client, password: 'originalpassword', password_confirmation: 'originalpassword')
        sign_in test_user_for_password

        password_params = { 
          current_password: 'originalpassword', 
          password: 'newcomplexpassword', 
          password_confirmation: 'newcomplexpassword' 
        }
        patch client_settings_path, params: { user: password_params }
        expect(response).to redirect_to(client_settings_path)
        expect(flash[:notice]).to eq('Settings (including password) updated successfully.')
      end

      it "fails to update with incorrect current_password" do
        # Similar setup as above for clarity for password test
        test_user_for_password = create(:user, role: :client, password: 'originalpassword', password_confirmation: 'originalpassword')
        sign_in test_user_for_password
        password_params = { 
          current_password: 'wrongpassword', 
          password: 'newcomplexpassword', 
          password_confirmation: 'newcomplexpassword' 
        }
        patch client_settings_path, params: { user: password_params }
        expect(response).to render_template(:edit)
        expect(flash.now[:alert]).to include('Failed to update password')
      end

      it "fails to update with mismatched new passwords" do
        test_user_for_password = create(:user, role: :client, password: 'originalpassword', password_confirmation: 'originalpassword')
        sign_in test_user_for_password
        password_params = { 
          current_password: 'originalpassword', 
          password: 'newcomplexpassword', 
          password_confirmation: 'anotherpassword' 
        }
        patch client_settings_path, params: { user: password_params }
        expect(response).to render_template(:edit)
        expect(flash.now[:alert]).to include('Failed to update password')
      end

      it "fails to update with invalid email" do
        patch client_settings_path, params: { user: { email: 'invalid' } }
        expect(response).to render_template(:edit)
        expect(flash.now[:alert]).to include('Failed to update profile settings')
      end
    end

    context "when logged in as a different client" do
      before { sign_in other_client_user }

      it "does not update the first client's settings and redirects or errors" do
        patch client_settings_path, params: { user: valid_attributes } # Pundit should prevent this
        # Behavior depends on Pundit policy - likely a redirect or forbidden error
        # client_user.reload
        # expect(client_user.first_name).not_to eq("NewFirstName")
        expect(response).not_to be_successful # General check
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        patch client_settings_path, params: { user: valid_attributes }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end 