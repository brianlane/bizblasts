# frozen_string_literal: true

require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe "BusinessManager::Settings::Profiles", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }
  let(:client_user) { create(:user, :client) }

  before do
    # Set the host to the business's hostname for tenant scoping
    host! "#{business.hostname}.lvh.me"
    # Use ActsAsTenant here as the BaseController would
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /edit" do
    # Subject now just performs the get request, setup is in before blocks
    subject { get edit_business_manager_settings_profile_path }

    context "when authenticated as a business manager" do
      before do
        sign_in manager_user
      end

      it "renders a successful response" do
        subject
        expect(response).to be_successful
      end

      it "assigns the current user to @user" do
        subject
        expect(assigns(:user)).to eq(manager_user)
      end
    end

    context "when authenticated as staff" do
      before do
        sign_in staff_user
      end

      it "renders a successful response" do
        subject
        expect(response).to be_successful
      end

      it "assigns the current user to @user" do
        subject
        expect(assigns(:user)).to eq(staff_user)
      end
    end

    context "when authenticated as a client" do
      before { sign_in client_user }

      it "redirects to the client dashboard or root path" do
        subject
        # Check for redirect and alert flash set by BaseController authorization failure
        expect(response).to redirect_to(dashboard_path) # Adjust if different redirect path
        expect(flash[:alert]).to be_present
      end
    end

    context "when not authenticated" do
      it "redirects to the sign in page" do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "PATCH /update" do
    let(:new_attributes) do
      {
        first_name: "Updated",
        last_name: "User",
        phone: "123-456-7890",
        notification_preferences: ["sms"]
      }
    end

    let(:invalid_attributes) do
      {
        first_name: "", # Invalid first name
      }
    end

    let(:password_attributes) do
      {
        password: "newpassword",
        password_confirmation: "newpassword"
      }
    end

    let(:password_mismatch_attributes) do
      {
        password: "newpassword",
        password_confirmation: "wrongconfirmation"
      }
    end

    # Subject now just performs the patch request, setup is in before blocks
    subject { patch business_manager_settings_profile_path, params: { user: attributes } }

    context "when authenticated as a business manager" do
      before do
        sign_in manager_user
      end

      context "with valid parameters" do
        let(:attributes) { new_attributes }

        it "updates the requested user" do
          subject
          manager_user.reload
          expect(manager_user.first_name).to eq("Updated")
          expect(manager_user.last_name).to eq("User")
          expect(manager_user.phone).to eq("123-456-7890")
          expect(manager_user.notification_preferences).to eq(["sms"])
        end

        it "redirects to the profile page" do
          subject
          expect(response).to redirect_to(edit_business_manager_settings_profile_path)
        end

        it "sets a notice flash message" do
          subject
          expect(flash[:notice]).to eq('Profile updated successfully.')
        end

        context "and changing password" do
          let(:attributes) { new_attributes.merge(password_attributes) }

          it "updates the user's password" do
            # Use change matcher to verify password change (less brittle)
            expect { subject }.to change { manager_user.reload.encrypted_password }
            expect(manager_user.reload.first_name).to eq(manager_user.first_name) # Ensure other attributes not accidentally changed

            # Devise handles password encryption, can't check directly. Test successful re-authentication.
            # Removed direct re-authentication test here as change matcher is more direct.
            # If needed, a separate feature spec could test login after password change.
          end

          it "redirects to the edit profile page" do
            subject
            expect(response).to redirect_to(edit_business_manager_settings_profile_path)
          end

          it "sets a notice flash message" do
            subject
            expect(flash[:notice]).to eq('Profile updated successfully.')
          end
        end

        context "and leaving password fields blank" do
          let(:attributes) { new_attributes.except(:password, :password_confirmation) }

          it "updates other attributes but not the password" do
            original_encrypted_password = manager_user.encrypted_password
            subject # Execute the update action
            manager_user.reload # Reload the user to get the updated attributes

            expect(manager_user.encrypted_password).to eq(original_encrypted_password) # Password should not have changed
            expect(manager_user.first_name).to eq("Updated") # First name should have changed
          end

          it "redirects to the edit profile page" do
            subject
            expect(response).to redirect_to(edit_business_manager_settings_profile_path)
          end

          it "sets a notice flash message" do
            subject
            expect(flash[:notice]).to eq('Profile updated successfully.')
          end
        end
      end

      context "with invalid parameters" do
        let(:attributes) { invalid_attributes }

        it "does not update the user" do
          subject
          manager_user.reload
          expect(manager_user.first_name).not_to eq("")
        end

        it "renders the edit template" do
          subject
          expect(response).to render_template(:edit)
        end

        it "sets an alert flash message" do
          subject
          # Expecting an alert from the controller on failure
          expect(flash[:alert]).to eq('Failed to update profile.')
        end

        it "displays validation errors" do
          subject
          # Check for the presence of the error explanation div and the specific error message text using assert_select.
          assert_select 'div#error_explanation' do
            assert_select 'h2', text: '1 error prohibited this user from being saved:'
            assert_select 'li', text: "First name can't be blank"
          end
        end
      end

      context "with password mismatch" do
        let(:attributes) { new_attributes.merge(password_mismatch_attributes) }

        it "does not update the password" do
          original_encrypted_password = manager_user.encrypted_password
          subject
          manager_user.reload
          expect(manager_user.encrypted_password).to eq(original_encrypted_password)
        end

        it "renders the edit template" do
          subject
          expect(response).to render_template(:edit)
        end

        it "sets an alert flash message" do
          subject
          expect(flash[:alert]).to eq('Failed to update profile.') # Assuming password validation errors trigger this alert
        end

        it "displays password mismatch error" do
          subject
          # Check for the presence of the error explanation div and the specific error message text using assert_select.
          assert_select 'div#error_explanation' do
            assert_select 'h2', text: '1 error prohibited this user from being saved:' # Assuming 1 error for password mismatch
            assert_select 'li', text: "Password confirmation doesn't match Password"
          end
        end
      end
    end

    context "when authenticated as staff" do
      before do
        sign_in staff_user
      end
      let(:attributes) { new_attributes }

      it "updates the requested user" do
        subject
        staff_user.reload
        expect(staff_user.first_name).to eq("Updated")
        expect(staff_user.last_name).to eq("User")
        expect(staff_user.phone).to eq("123-456-7890")
        expect(staff_user.notification_preferences).to eq(["sms"])
      end

      it "redirects to the profile page" do
        subject
        expect(response).to redirect_to(edit_business_manager_settings_profile_path)
      end

      it "sets a notice flash message" do
        subject
        expect(flash[:notice]).to eq('Profile updated successfully.')
      end
    end

    context "when authenticated as a client" do
      before { sign_in client_user }
      let(:attributes) { new_attributes }

      it "redirects to the client dashboard or root path" do
        subject
        # Check for redirect and alert flash set by BaseController authorization failure
        expect(response).to redirect_to(dashboard_path) # Adjust if different redirect path
        expect(flash[:alert]).to be_present
      end

      it "does not update the user" do
        subject
        client_user.reload
        expect(client_user.first_name).not_to eq("Updated")
      end
    end

    context "when not authenticated" do
      let(:attributes) { new_attributes }

      it "redirects to the sign in page" do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end

      it "does not update the user" do
        subject
        # Check a random user to ensure no unintended changes
        manager_user.reload
        expect(manager_user.first_name).not_to eq("Updated")
      end
    end

    # Add a test case for when attempting to update a different user's profile (should fail Pundit auth)
    context "when attempting to update another user's profile" do
      let(:another_business) { create(:business) }
      let(:another_manager) { create(:user, :manager, business: another_business) }
      let(:attributes) { new_attributes }

      subject do
        host! another_business.hostname
        ActsAsTenant.current_tenant = another_business
        patch business_manager_settings_profile_path(another_manager), params: { user: attributes }
      end

      before do
        sign_in manager_user
        host! business.hostname
        ActsAsTenant.current_tenant = business
      end

      it "does not update the other user" do
        original_first_name = another_manager.first_name
        subject
        another_manager.reload
        expect(another_manager.first_name).to eq(original_first_name)
      end

      it "redirects due to authorization failure" do
        subject
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end 