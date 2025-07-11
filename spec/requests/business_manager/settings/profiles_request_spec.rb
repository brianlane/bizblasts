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
        notification_preferences: {
          email_booking_notifications: '1'
        }
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
          expect(manager_user.notification_preferences).to eq({ 'email_booking_notifications' => true })
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
        expect(staff_user.notification_preferences).to eq({ 'email_booking_notifications' => true })
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

    context "when updating notification preferences" do
      before do
        sign_in manager_user
      end
      
      let(:attributes) do
        {
          first_name: 'NewFirstName',
          last_name: 'NewLastName',
          phone: '987-654-3210',
          notification_preferences: {
            email_booking_notifications: '1'
          }
        }
      end

      it "updates the requested user" do
        subject
        manager_user.reload
        expect(manager_user.first_name).to eq('NewFirstName')
        expect(manager_user.last_name).to eq('NewLastName')
        expect(manager_user.phone).to eq('987-654-3210')
        expect(manager_user.notification_preferences).to eq({ 'email_booking_notifications' => true })
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
  end

  # Production issue tests based on screenshot and bug report
  describe 'notification preferences production issues' do
    let(:manager_user) { create(:user, :manager, business: business) }
    
    before do
      sign_in manager_user
    end

    context 'when updating profile with notification preferences checked' do
      it 'saves notification preferences correctly (currently failing in prod)' do
        # This test replicates the exact scenario from the screenshot
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Ftest',
            last_name: 'Ltest', 
            email: 'brianlanefanmail@gmail.com',
            notification_preferences: {
              'email_booking_notifications' => '1',
              'email_order_notifications' => '1',
              'email_customer_notifications' => '1',
              'email_payment_notifications' => '1'
            }
          }
        }

        expect(response).to redirect_to(edit_business_manager_settings_profile_path)
        expect(flash[:notice]).to eq('Profile updated successfully.')
        
        # Verify the preferences were actually saved to the database
        manager_user.reload
        expect(manager_user.notification_preferences).to be_present
        expect(manager_user.notification_preferences['email_booking_notifications']).to be true
        expect(manager_user.notification_preferences['email_order_notifications']).to be true
        expect(manager_user.notification_preferences['email_customer_notifications']).to be true
        expect(manager_user.notification_preferences['email_payment_notifications']).to be true
      end

      it 'handles mixed notification preferences correctly' do
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Test',
            last_name: 'User',
            notification_preferences: {
              'email_booking_notifications' => '1',   # checked
              'email_order_notifications' => '0',     # unchecked
              'email_customer_notifications' => '1',  # checked
              'email_payment_notifications' => '0'    # unchecked
            }
          }
        }

        manager_user.reload
        expect(manager_user.notification_preferences['email_booking_notifications']).to be true
        expect(manager_user.notification_preferences['email_order_notifications']).to be false
        expect(manager_user.notification_preferences['email_customer_notifications']).to be true
        expect(manager_user.notification_preferences['email_payment_notifications']).to be false
      end

      it 'handles empty/nil notification preferences' do
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Test',
            last_name: 'User',
            notification_preferences: {}
          }
        }

        manager_user.reload
        # Should preserve existing preferences or set to empty hash (empty hash is not present but is not nil)
        expect(manager_user.notification_preferences).not_to be_nil
        expect(manager_user.notification_preferences).to eq({})
      end

      it 'handles form submission without notification preferences key' do
        # This might happen if JavaScript fails or form is malformed
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Test',
            last_name: 'User'
          }
        }

        expect(response).to redirect_to(edit_business_manager_settings_profile_path)
        expect(flash[:notice]).to eq('Profile updated successfully.')
        
        # Should not crash and preferences should remain intact
        manager_user.reload
        expect(manager_user.first_name).to eq('Test')
      end
    end

    context 'parameter handling debugging' do
      it 'logs the exact parameters being received' do
        allow(Rails.logger).to receive(:debug)
        
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Debug',
            notification_preferences: {
              'email_booking_notifications' => '1'
            }
          }
        }

        # Check if we can capture the actual parameters in the controller
        # This will help us debug the exact issue
        expect(response).to redirect_to(edit_business_manager_settings_profile_path)
      end
    end

    context 'checkbox form field behavior' do
      it 'handles Rails checkbox field behavior correctly' do
        # Rails checkboxes send ['0', '1'] for checked boxes and ['0'] for unchecked
        # This might be the source of the bug
        
        patch business_manager_settings_profile_path, params: {
          user: {
            first_name: 'Checkbox',
            last_name: 'Test',
            notification_preferences: {
              'email_booking_notifications' => ['0', '1'], # Checked checkbox
              'email_order_notifications' => ['0'],        # Unchecked checkbox
            }
          }
        }

        manager_user.reload
        # Should handle Rails checkbox format correctly
        expect(manager_user.notification_preferences['email_booking_notifications']).to be true
        expect(manager_user.notification_preferences['email_order_notifications']).to be false
      end
    end

    context 'business email integration after preferences fix' do
      it 'sends business emails when preferences are properly saved' do
        # Clear deliveries before test
        ActionMailer::Base.deliveries.clear
        
        # Enable deliveries for this test
        original_perform_deliveries = ActionMailer::Base.perform_deliveries
        ActionMailer::Base.perform_deliveries = true
        
        begin
        # First, ensure preferences are saved correctly
        patch business_manager_settings_profile_path, params: {
          user: {
            notification_preferences: {
              'email_booking_notifications' => '1',
              'email_customer_notifications' => '1'
            }
          }
        }

        manager_user.reload
        expect(manager_user.notification_preferences['email_booking_notifications']).to be true

        # Now test that business emails actually send
        booking = create(:booking, business: business)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
        ensure
          # Restore original setting
          ActionMailer::Base.perform_deliveries = original_perform_deliveries
        end
      end
    end
  end

  describe 'universal unsubscribe UI' do
    before do
      sign_in manager_user
      manager_user.update!(unsubscribed_at: Time.current)
    end

    it "shows the 'Unsubscribed Successfully' banner but keeps notification toggles enabled for granular control" do
      get edit_business_manager_settings_profile_path
      expect(response.body).to include("Unsubscribed Successfully")
      expect(response.body).to include("You have globally unsubscribed from all marketing and notification emails")
      expect(response.body).to include("Resubscribe")
      # Notification checkboxes should remain enabled for granular control
      expect(response.body).not_to include("fieldset disabled")
      # Should show the unsubscribe banner (not the flash message from button click)
      expect(response.body).to include("You have globally unsubscribed from all marketing and notification emails")
    end
  end
end 