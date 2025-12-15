# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Custom Domain Member Actions', type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:business) do
    create(
      :business,
      host_type: 'custom_domain',
      hostname: 'example.com'
    )
  end

  before do
    sign_in admin_user, scope: :admin_user
  end

  describe 'HTTP method restrictions' do
    it 'disallows GET for start_domain_setup' do
      get start_domain_setup_admin_business_path(business.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'disallows GET for restart_domain_monitoring' do
      get restart_domain_monitoring_admin_business_path(business.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'disallows GET for force_activate_domain' do
      get force_activate_domain_admin_business_path(business.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'disallows GET for disable_custom_domain' do
      get disable_custom_domain_admin_business_path(business.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST actions redirect to numeric-ID show path' do
    it 'POST start_domain_setup redirects to /admin/businesses/:id' do
      service = instance_double(CnameSetupService, start_setup!: { success: true, message: 'ok' })
      allow(CnameSetupService).to receive(:new).and_return(service)

      post start_domain_setup_admin_business_path(business.id)
      expect(response).to redirect_to(admin_business_path(business.id))
    end

    it 'POST restart_domain_monitoring redirects to /admin/businesses/:id' do
      service = instance_double(CnameSetupService, restart_monitoring!: { success: true, message: 'ok' })
      allow(CnameSetupService).to receive(:new).and_return(service)

      post restart_domain_monitoring_admin_business_path(business.id)
      expect(response).to redirect_to(admin_business_path(business.id))
    end

    it 'POST force_activate_domain redirects to /admin/businesses/:id' do
      service = instance_double(CnameSetupService, force_activate!: { success: true, message: 'ok' })
      allow(CnameSetupService).to receive(:new).and_return(service)

      post force_activate_domain_admin_business_path(business.id)
      expect(response).to redirect_to(admin_business_path(business.id))
    end

    it 'POST disable_custom_domain redirects to /admin/businesses/:id' do
      removal_service = instance_double(DomainRemovalService, remove_domain!: { success: true, message: 'removed' })
      allow(DomainRemovalService).to receive(:new).and_return(removal_service)

      post disable_custom_domain_admin_business_path(business.id)
      expect(response).to redirect_to(admin_business_path(business.id))
    end
  end
end


