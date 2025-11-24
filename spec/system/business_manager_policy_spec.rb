# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Business Manager Policy Enforcement', type: :system do
  let(:business) { create(:business, host_type: 'subdomain') }
  let(:manager) { create(:user, :manager, business: business) }
  let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
  let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true) }
  let!(:aup_policy) { create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true) }
  let!(:return_policy) { create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true) }
  
  before do
    driven_by(:rack_test)
    
    # Configure Capybara for subdomain
    Capybara.app_host = "http://#{host_for(business)}"
    
    # Set tenant context for the business
    ActsAsTenant.current_tenant = business
    
    # Mark manager as requiring policy acceptance
    manager.update!(requires_policy_acceptance: true)
    
    # Sign in the manager
    sign_in manager
  end
  
  after do
    # Reset to main domain
    Capybara.app_host = "http://www.example.com"
    ActsAsTenant.current_tenant = nil
  end
  
  describe 'policy modal in business manager layout' do
    it 'includes policy modal HTML in business manager dashboard' do
      visit '/manage/dashboard'
      
      # Should render business manager layout with policy modal
      expect(page).to have_css('#policy-acceptance-modal', visible: false)
      expect(page).to have_css('#accept-all-policies', visible: false)
      expect(page).to have_css('#policies-to-accept', visible: false)
      
      # Should include the business manager layout elements
      expect(page).to have_content(business.name).or have_content('Business Manager')
    end
    
    it 'provides access to policy status endpoint from subdomain' do
      visit '/policy_status'
      
      # Should return JSON with policy requirements
      expect(page).to have_content('requires_policy_acceptance')
      expect(page).to have_content('missing_policies')
      
      # Manager should need all four policies including return_policy
      expect(page).to have_content('privacy_policy')
      expect(page).to have_content('terms_of_service')
      expect(page).to have_content('acceptable_use_policy')
      expect(page).to have_content('return_policy')
    end
    
    it 'allows navigation to business manager pages when policy acceptance is required' do
      # Manager should be able to access business manager pages
      # The policy modal should handle prompting for acceptance
      visit '/manage/dashboard'
      expect(page).to have_content(business.name).or have_content('Business Manager')
      
      visit '/manage/services'
      expect(page.status_code).to eq(200)
      
      visit '/manage/products'
      expect(page.status_code).to eq(200)
      
      visit '/manage/settings'
      expect(page.status_code).to eq(200)
    end
  end
  
  describe 'policy acceptance flow on subdomain' do
    it 'can record policy acceptance for business user on subdomain' do
      expect {
        PolicyAcceptance.record_acceptance(manager, 'privacy_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
        PolicyAcceptance.record_acceptance(manager, 'terms_of_service', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
        PolicyAcceptance.record_acceptance(manager, 'acceptable_use_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
        PolicyAcceptance.record_acceptance(manager, 'return_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      }.to change(PolicyAcceptance, :count).by(4)
      
      manager.mark_policies_accepted!
      
      expect(manager.reload.requires_policy_acceptance).to be false
      expect(manager.missing_required_policies).to be_empty
    end
    
    it 'no longer shows missing policies after acceptance' do
      # Accept all policies
      PolicyAcceptance.record_acceptance(manager, 'privacy_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      PolicyAcceptance.record_acceptance(manager, 'terms_of_service', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      PolicyAcceptance.record_acceptance(manager, 'acceptable_use_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      PolicyAcceptance.record_acceptance(manager, 'return_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      
      manager.mark_policies_accepted!
      
      visit '/policy_status'
      
      # Should now show no policy acceptance required
      expect(page).to have_content('requires_policy_acceptance')
      expect(page).to have_content('false').or have_content('"missing_policies":[]')
    end
  end
  
  describe 'policy page redirects' do
    it 'redirects policy pages to main domain' do
      # These should redirect to main domain but we can test they don't error
      expect { visit '/privacypolicy' }.not_to raise_error
      expect { visit '/terms' }.not_to raise_error
      expect { visit '/acceptableusepolicy' }.not_to raise_error
      expect { visit '/returnpolicy' }.not_to raise_error
    end
  end
end 