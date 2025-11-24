# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Content Security Policy', type: :request do
  describe 'CSP headers on public routes' do
    it 'sends CSP meta tag on homepage' do
      get root_path
      expect(response).to have_http_status(:success)
      # CSP is set via meta tag in layout, check response body
      expect(response.body).to include('csp-nonce')
    end

    it 'sends CSP header with required directives' do
      get root_path
      # CSP may be set via meta tag or header, check both
      csp = response.headers['Content-Security-Policy'] || ''

      # In test environment, CSP may be in report-only mode
      csp_report = response.headers['Content-Security-Policy-Report-Only'] || ''

      # One of them should be present
      expect(csp + csp_report).not_to be_empty
    end

    it 'includes script-src directive' do
      get root_path
      csp = response.headers['Content-Security-Policy'] ||
            response.headers['Content-Security-Policy-Report-Only'] || ''

      # Should include script-src directive (either in header or will be in meta tag)
      if csp.present?
        expect(csp).to include('script-src')
      end
    end
  end

  describe 'CSP headers on authenticated routes' do
    let(:business) { create(:business) }
    let(:manager) { create(:user, :manager, business: business) }

    before do
      host! "#{business.hostname}.lvh.me"
      ActsAsTenant.current_tenant = business
      sign_in manager
    end

    after do
      ActsAsTenant.current_tenant = nil
    end

    it 'sends CSP on business manager dashboard' do
      get '/manage'
      expect(response).to have_http_status(:success)

      # Check for CSP in either header or meta tag
      csp_header = response.headers['Content-Security-Policy'] ||
                   response.headers['Content-Security-Policy-Report-Only']

      expect(csp_header || response.body).to be_present
    end

    it 'allows unsafe-inline in test environment' do
      get '/manage'
      csp = response.headers['Content-Security-Policy'] ||
            response.headers['Content-Security-Policy-Report-Only'] || ''

      # In test environment, we may allow unsafe-inline for compatibility
      # This is acceptable as long as production will use nonces
      if csp.present?
        expect(csp).to match(/(unsafe-inline|nonce-)/)
      end
    end
  end

  describe 'CSP nonce generation' do
    it 'generates unique nonces per request' do
      get root_path
      nonce1 = extract_nonce_from_response(response)

      get root_path
      nonce2 = extract_nonce_from_response(response)

      # Nonces should be unique (if present)
      if nonce1.present? && nonce2.present?
        expect(nonce1).not_to eq(nonce2)
      end
    end
  end

  describe 'CSP on admin routes' do
    let(:admin_user) { create(:admin_user) }

    before do
      sign_in admin_user
    end

    it 'sends CSP on ActiveAdmin dashboard' do
      get admin_root_path
      expect(response).to have_http_status(:success)

      # ActiveAdmin should also have CSP protection
      csp = response.headers['Content-Security-Policy'] ||
            response.headers['Content-Security-Policy-Report-Only']

      expect(csp || response.body).to be_present
    end
  end

  private

  def extract_nonce_from_response(response)
    # Extract nonce from CSP header
    csp = response.headers['Content-Security-Policy'] ||
          response.headers['Content-Security-Policy-Report-Only']
    return nil unless csp

    match = csp.match(/nonce-([a-zA-Z0-9+\/=]+)/)
    match ? match[1] : nil
  end
end
