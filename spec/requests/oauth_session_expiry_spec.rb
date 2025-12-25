# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OAuth Session Expiry', type: :request do
  describe 'Registration with OAuth data' do
    context 'when user provides password (normal registration)' do
      it 'allows client registration to succeed' do
        # User submits form WITH password (normal registration, not OAuth)
        post client_registration_path, params: {
          user: {
            email: 'normal@example.com',
            first_name: 'Normal',
            last_name: 'User',
            password: 'SecurePassword123!',
            password_confirmation: 'SecurePassword123!'
          },
          policy_acceptances: {
            terms_of_service: '1',
            privacy_policy: '1',
            acceptable_use_policy: '1',
            return_policy: '1'
          }
        }

        # Should create user successfully
        expect(User.find_by(email: 'normal@example.com')).to be_present
      end

      it 'allows business registration to succeed' do
        # User submits business registration with password
        post business_registration_path, params: {
          user: {
            email: 'businessowner@example.com',
            first_name: 'Business',
            last_name: 'Owner',
            password: 'SecurePassword123!',
            password_confirmation: 'SecurePassword123!',
            business_attributes: {
              name: 'Test Business',
              industry: 'consulting',
              phone: '555-1234',
              email: 'contact@test.com',
              address: '123 Main St',
              city: 'Test',
              state: 'CA',
              zip: '12345',
              description: 'Test',
              subdomain: 'testbiz'
            }
          },
          policy_acceptances: {
            terms_of_service: '1',
            privacy_policy: '1',
            acceptable_use_policy: '1',
            return_policy: '1'
          }
        }

        # Should create user and business successfully
        user = User.find_by(email: 'businessowner@example.com')
        expect(user).to be_present
        expect(user.business).to be_present
      end
    end
  end

  describe 'OauthRegistration concern integration' do
    it 'defines OAUTH_SESSION_TIMEOUT constant' do
      expect(OauthRegistration::OAUTH_SESSION_TIMEOUT).to eq(10.minutes)
    end

    it 'is included in Client::RegistrationsController' do
      expect(Client::RegistrationsController.included_modules).to include(OauthRegistration)
    end

    it 'is included in Business::RegistrationsController' do
      expect(Business::RegistrationsController.included_modules).to include(OauthRegistration)
    end
  end
end
