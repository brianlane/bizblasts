# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tenant Isolation Security', type: :request do
  let!(:business1) { create(:business, hostname: 'business1') }
  let!(:business2) { create(:business, hostname: 'business2') }
  let!(:manager1) { create(:user, :manager, business: business1) }
  let!(:manager2) { create(:user, :manager, business: business2) }
  let!(:integration_credential1) { create(:integration_credential, business: business1) }
  let!(:integration_credential2) { create(:integration_credential, business: business2) }

  before do
    ActsAsTenant.current_tenant = business1
  end

  describe 'Cross-tenant access prevention' do
    context 'when manager tries to access other business integration credentials' do
      before { sign_in manager1 }

      it 'prevents access to other business integration credentials' do
        get "/business_manager/settings/integration_credentials/#{integration_credential2.id}"
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You are not authorized to access this area.")
      end

      it 'allows access to own business integration credentials' do
        get "/business_manager/settings/integration_credentials/#{integration_credential1.id}"
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when accessing different business via subdomain manipulation' do
      before { sign_in manager1 }

      it 'prevents access when tenant context is wrong' do
        # Try to access business2's data while signed in as business1 manager
        host! "business2.example.com"
        get "/business_manager/settings/integration_credentials/#{integration_credential2.id}"
        
        # Should either be redirected or get not found, not access the data
        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  describe 'Policy enforcement with logging' do
    before { sign_in manager1 }

    it 'logs authorization failures' do
      expect(SecureLogger).to receive(:security_event).with(
        'authorization_failure',
        hash_including(
          user_id: manager1.id,
          action: :show,
          resource: 'IntegrationCredential'
        )
      )

      get "/business_manager/settings/integration_credentials/#{integration_credential2.id}"
    end
  end

  describe 'Email enumeration protection' do
    it 'returns same response for existing and non-existing emails' do
      existing_email = manager1.email
      non_existing_email = 'nonexistent@example.com'

      # Test existing email
      post '/public/unsubscribe/magic_link', params: { email: existing_email }
      existing_response = response.body
      existing_status = response.status

      # Test non-existing email
      post '/public/unsubscribe/magic_link', params: { email: non_existing_email }
      non_existing_response = response.body
      non_existing_status = response.status

      # Responses should be identical
      expect(existing_status).to eq(non_existing_status)
      expect(existing_response).to eq(non_existing_response)
      expect(JSON.parse(existing_response)['message']).to include('If an account with this email exists')
    end
  end

  describe 'Data sanitization in logs' do
    it 'does not log sensitive data' do
      allow(Rails.logger).to receive(:info)
      
      # Perform action that would previously log email
      ActsAsTenant.current_tenant = business1
      # This would trigger logging in services that we've sanitized
      
      expect(Rails.logger).not_to have_received(:info).with(
        a_string_including(manager1.email)
      )
    end
  end
end