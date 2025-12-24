# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OAuth User Password Reset', type: :system do
  let(:business) { create(:business) }

  # OAuth user created without a password
  let(:oauth_user) do
    create(:user, :client,
           email: 'oauth_user@example.com',
           provider: 'google_oauth2',
           uid: '12345',
           password: Devise.friendly_token[0, 20], # Random password they don't know
           password_confirmation: nil)
  end

  before do
    driven_by(:rack_test)
  end

  describe 'password reset flow for OAuth users' do
    it 'allows OAuth users to request password reset' do
      visit new_user_password_path

      fill_in 'Email', with: oauth_user.email
      click_button 'Send me reset password instructions'

      expect(page).to have_content('You will receive an email with instructions')
      expect(ActionMailer::Base.deliveries.count).to eq(1)

      # Verify email was sent to OAuth user
      email = ActionMailer::Base.deliveries.last
      expect(email.to).to include(oauth_user.email)
      expect(email.subject).to match(/reset password/i)
    end

    it 'allows OAuth users to set a new password via reset token' do
      # Generate reset token for OAuth user
      oauth_user.send_reset_password_instructions

      # Extract reset token from email
      email = ActionMailer::Base.deliveries.last
      reset_token = email.body.to_s.match(/reset_password_token=([^"&\s]+)/)[1]

      # Visit password reset page with token
      visit edit_user_password_path(reset_password_token: reset_token)

      # Set new password
      fill_in 'New password', with: 'NewSecurePassword123!'
      fill_in 'Confirm new password', with: 'NewSecurePassword123!'
      click_button 'Change my password'

      expect(page).to have_content('Your password has been changed successfully')

      # Verify user is signed in after password reset (client users go to dashboard)
      expect(page).to have_current_path(dashboard_path, ignore_query: true)
    end

    it 'allows OAuth users to sign in with password after setting it' do
      # OAuth user sets a password
      new_password = 'NewSecurePassword123!'
      oauth_user.reset_password(new_password, new_password)

      # Sign out if signed in
      visit destroy_user_session_path if page.has_css?('a', text: 'Sign out')

      # Sign in with email/password (not OAuth)
      visit new_user_session_path

      # Use form selector to avoid ambiguous button match (OAuth buttons also present)
      within("form[action='#{user_session_path}']") do
        fill_in 'Email', with: oauth_user.email
        fill_in 'Password', with: new_password
        click_button 'Sign In'
      end

      expect(page).to have_content('Signed in successfully')
      expect(page).to have_current_path(dashboard_path, ignore_query: true)
    end

    it 'allows OAuth users to continue using OAuth after setting password' do
      # OAuth user sets a password
      new_password = 'NewSecurePassword123!'
      oauth_user.reset_password(new_password, new_password)

      # They should still be able to use OAuth
      # Note: This is verified by checking user model still has provider/uid
      oauth_user.reload
      expect(oauth_user.provider).to eq('google_oauth2')
      expect(oauth_user.uid).to eq('12345')
      expect(oauth_user.encrypted_password).to be_present

      # Both OAuth and password authentication should work
      expect(oauth_user.oauth_user?).to be true
      expect(oauth_user.valid_password?(new_password)).to be true
    end
  end

  describe 'password requirements for OAuth users' do
    it 'does not require password on user creation for OAuth users' do
      # OAuth users are created without needing password confirmation
      user = User.new(
        email: 'new_oauth@example.com',
        first_name: 'OAuth',
        last_name: 'User',
        provider: 'google_oauth2',
        uid: '67890',
        password: Devise.friendly_token[0, 20],
        role: :client
      )

      expect(user).to be_valid
      expect(user.save).to be true
    end

    it 'requires password only when setting one for OAuth users' do
      # When OAuth user tries to set password, both password and confirmation required
      oauth_user.password = 'NewPassword123!'
      oauth_user.password_confirmation = 'DifferentPassword'

      expect(oauth_user).not_to be_valid
      expect(oauth_user.errors[:password_confirmation]).to include("doesn't match Password")
    end
  end
end
