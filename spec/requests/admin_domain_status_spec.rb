# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Domain Status API', type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:business) do
    create(:business,
      host_type: 'custom_domain',
      hostname: 'example.com',
      status: 'cname_monitoring',
      cname_monitoring_active: true,
      cname_check_attempts: 3
    )
  end

  before do
    sign_in admin_user, scope: :admin_user
  end

  describe 'GET /admin/businesses/:id/domain_status' do
    context 'with monitoring active business' do
      let(:dns_result) do
        {
          verified: true,
          target: 'bizblasts.onrender.com',
          checked_at: Time.current,
          error: nil
        }
      end

      before do
        allow(CnameDnsChecker).to receive(:new).and_return(
          instance_double(CnameDnsChecker, verify_cname: dns_result)
        )
      end

      it 'returns business status with live DNS check' do
        get "/admin/businesses/#{business.id}/domain_status"

        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['business_id']).to eq(business.id)
        expect(json_response['domain']).to eq('example.com')
        expect(json_response['status']).to eq('cname_monitoring')
        expect(json_response['monitoring_active']).to be true
        expect(json_response['check_attempts']).to eq(3)
        
        expect(json_response['dns_check']).to be_present
        expect(json_response['dns_check']['verified']).to be true
        expect(json_response['dns_check']['target']).to eq('bizblasts.onrender.com')
      end
    end

    # Regression for Bugbot MEDIUM: "DNS status flag ignores dual check".
    # On Caddy the admin "✅ DNS Verified" badge must mirror the same gate
    # used to flip cname_success! (i.e. require BOTH apex and www to
    # verify), not the legacy single-host CnameDnsChecker pass that can
    # show green when only the canonical host has the right A record.
    context 'with Caddy mode and only the canonical host verified' do
      let(:single_host_pass) do
        {
          verified: true,
          target: '99.102.205.60',
          checked_at: Time.current,
          error: nil
        }
      end

      before do
        allow(DomainProvider).to receive(:caddy?).and_return(true)
        allow(CnameDnsChecker).to receive(:new).and_return(
          instance_double(CnameDnsChecker, verify_cname: single_host_pass)
        )

        dual = instance_double(DualDomainVerifier)
        allow(DualDomainVerifier).to receive(:new).and_return(dual)
        allow(dual).to receive(:verify_both_domains).and_return(
          overall_verified: false,
          apex_domain: { verified: true },
          www_domain:  { verified: false }
        )
      end

      it 'reports dns_check.verified=false because dual check failed on www' do
        get "/admin/businesses/#{business.id}/domain_status"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response['dns_check']).to be_present
        expect(json_response['dns_check']['verified']).to be false
        expect(json_response['dns_check']['target']).to eq('99.102.205.60')
      end
    end

    context 'with inactive monitoring business' do
      before do
        business.update!(cname_monitoring_active: false, status: 'cname_active')
      end

      it 'returns business status without DNS check' do
        get "/admin/businesses/#{business.id}/domain_status"

        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['business_id']).to eq(business.id)
        expect(json_response['status']).to eq('cname_active')
        expect(json_response['monitoring_active']).to be false
        expect(json_response['dns_check']).to be_nil
      end
    end

    context 'with DNS check error' do
      before do
        allow(CnameDnsChecker).to receive(:new).and_raise(StandardError.new('DNS resolution failed'))
      end

      it 'returns error response' do
        get "/admin/businesses/#{business.id}/domain_status"

        expect(response).to have_http_status(:internal_server_error)
        
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('DNS resolution failed')
      end
    end

    context 'without admin authentication' do
      before do
        sign_out admin_user
      end

      it 'redirects to login' do
        get "/admin/businesses/#{business.id}/domain_status"

        expect(response).to have_http_status(:redirect)
      end
    end
  end
end