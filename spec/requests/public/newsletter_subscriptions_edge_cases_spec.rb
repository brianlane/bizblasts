# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Newsletter Subscriptions Edge Cases', type: :request do
  let(:business) { create(:business, :with_subdomain) }

  before do
    ActsAsTenant.with_tenant(business) do
      host! TenantHost.host_for(business, nil)
    end
  end

  describe 'duplicate email handling' do
    context 'when email already exists as a customer' do
      let!(:existing_customer) do
        ActsAsTenant.with_tenant(business) do
          create(:tenant_customer,
                 business: business,
                 email: 'existing@example.com',
                 first_name: 'John',
                 last_name: 'Doe')
        end
      end

      it 'does not create duplicate customer' do
        ActsAsTenant.with_tenant(business) do
          expect {
            post newsletter_subscriptions_path,
                 params: { newsletter_subscription: { email: 'existing@example.com' } }
          }.not_to change(TenantCustomer, :count)

          expect(response).to redirect_to(tenant_root_path)
          follow_redirect!
          expect(flash[:notice]).to include("You're on the list")
        end
      end
    end

    context 'when email is already subscribed' do
      before do
        ActsAsTenant.with_tenant(business) do
          create(:tenant_customer,
                 business: business,
                 email: 'subscribed@example.com',
                 first_name: nil,
                 last_name: nil)
        end
      end

      it 'shows success message without creating duplicate' do
        ActsAsTenant.with_tenant(business) do
          expect {
            post newsletter_subscriptions_path,
                 params: { newsletter_subscription: { email: 'subscribed@example.com' } }
          }.not_to change(TenantCustomer, :count)

          expect(flash[:notice]).to include("You're on the list")
        end
      end
    end
  end

  describe 'email validation' do
    context 'when email is blank' do
      it 'shows error message' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: '' } }

        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(flash[:alert]).to include('Please provide an email address')
      end
    end

    context 'when email is only whitespace' do
      it 'treats as blank and shows error' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: '   ' } }

        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(flash[:alert]).to include('Please provide an email address')
      end
    end

    context 'when email has invalid format' do
      it 'shows appropriate error from CustomerLinker' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'not-an-email' } }

        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'guest conflict handling' do
    context 'when GuestConflictError is raised' do
      before do
        # Simulate a guest conflict scenario
        allow_any_instance_of(CustomerLinker).to receive(:find_or_create_guest_customer)
          .and_raise(GuestConflictError, 'Email already exists with different account type')
      end

      it 'shows the error message to user' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'conflict@example.com' } }

        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(flash[:alert]).to include('already exists with different account type')
      end
    end
  end

  describe 'error handling' do
    context 'when database error occurs' do
      before do
        allow_any_instance_of(CustomerLinker).to receive(:find_or_create_guest_customer)
          .and_raise(ActiveRecord::RecordInvalid, 'Database error')
      end

      it 'shows generic error message' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'test@example.com' } }

        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(flash[:alert]).to include("couldn't add your email")
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with(/Failed to subscribe email.*for business/)

        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'test@example.com' } }
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow_any_instance_of(CustomerLinker).to receive(:find_or_create_guest_customer)
          .and_raise(StandardError, 'Unexpected error')
      end

      it 'catches and handles gracefully' do
        expect {
          post newsletter_subscriptions_path,
               params: { newsletter_subscription: { email: 'test@example.com' } }
        }.not_to raise_error

        expect(flash[:alert]).to include("couldn't add your email")
      end
    end
  end

  describe 'fallback behavior' do
    context 'when return_to is not specified' do
      it 'redirects to tenant root' do
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'test@example.com' } }

        expect(response).to redirect_to(tenant_root_path)
      end
    end

    context 'when return_to is invalid' do
      it 'still redirects safely' do
        # Even with invalid return_to, should handle gracefully
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: 'test@example.com' } },
             headers: { 'HTTP_REFERER' => 'javascript:alert(1)' }

        expect(response).to redirect_to(tenant_root_path)
      end
    end
  end

  describe 'case sensitivity' do
    context 'when email has mixed case' do
      before do
        ActsAsTenant.with_tenant(business) do
          create(:tenant_customer,
                 business: business,
                 email: 'test@example.com',
                 first_name: nil,
                 last_name: nil)
        end
      end

      it 'finds existing customer regardless of case' do
        ActsAsTenant.with_tenant(business) do
          expect {
            post newsletter_subscriptions_path,
                 params: { newsletter_subscription: { email: 'TEST@EXAMPLE.COM' } }
          }.not_to change(TenantCustomer, :count)

          expect(flash[:notice]).to include("You're on the list")
        end
      end
    end
  end

  describe 'SQL injection prevention' do
    it 'safely handles malicious email input' do
      malicious_email = "'; DROP TABLE tenant_customers; --@example.com"

      expect {
        post newsletter_subscriptions_path,
             params: { newsletter_subscription: { email: malicious_email } }
      }.not_to change(TenantCustomer, :count)

      # Should fail validation, not execute SQL
      expect(flash[:alert]).to be_present
    end
  end
end
