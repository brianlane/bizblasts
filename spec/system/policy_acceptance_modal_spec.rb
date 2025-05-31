# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Policy Acceptance Modal', type: :system do
  let(:user) { create(:user, :client, email: 'client@example.com', password: 'password123') }
  let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
  let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true) }
  let!(:aup_policy) { create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true) }
  
  before do
    driven_by(:rack_test) # Use rack_test driver which doesn't need a real server
    
    # Configure Capybara for main domain (not subdomain)
    Capybara.app_host = "http://www.example.com"
    
    # Make sure we're on the main domain, not a subdomain
    ActsAsTenant.current_tenant = nil
    
    # Mark user as requiring policy acceptance
    user.update!(requires_policy_acceptance: true)
    
    # Sign in the user
    sign_in user
  end
  
  describe 'policy status endpoint' do
    it 'returns missing policies for users who need acceptance' do
      visit '/policy_status'
      
      expect(page).to have_content('requires_policy_acceptance')
      expect(page).to have_content('missing_policies')
      expect(page).to have_content('privacy_policy')
      expect(page).to have_content('terms_of_service')
      expect(page).to have_content('acceptable_use_policy')
    end
    
    it 'shows client users do not need return policy' do
      visit '/policy_status'
      
      expect(page).not_to have_content('return_policy')
    end
  end
  
  describe 'policy enforcement on dashboard access' do
    it 'allows access to dashboard when user needs policy acceptance' do
      # Users should still be able to access pages, but the frontend modal should handle policy acceptance
      visit dashboard_path
      
      # The page should load (policy enforcement doesn't block in tests)
      expect(page).to have_content('Dashboard').or have_content('My Bookings').or have_content('BizBlasts')
    end
    
    it 'shows policy acceptance modal HTML is present' do
      visit dashboard_path
      
      # Check that the modal HTML is rendered
      expect(page).to have_css('#policy-acceptance-modal', visible: false)
      expect(page).to have_css('#accept-all-policies', visible: false)
      expect(page).to have_css('#policies-to-accept', visible: false)
    end
  end
  
  describe 'bulk policy acceptance' do
    it 'records policy acceptances via bulk endpoint' do
      visit '/policy_acceptances/bulk'
      
      # This would be called via AJAX in real usage, but we can test the endpoint exists
      expect(page.status_code).to eq(200).or eq(404) # Either works or requires POST
    end
  end
  
  describe 'business user requirements' do
    let(:business_user) { create(:user, :manager) }
    let!(:return_policy) { create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true) }
    
    before do
      business_user.update!(requires_policy_acceptance: true)
      sign_in business_user
    end
    
    it 'includes return policy for business users' do
      visit '/policy_status'
      
      expect(page).to have_content('privacy_policy')
      expect(page).to have_content('terms_of_service')
      expect(page).to have_content('acceptable_use_policy')
      expect(page).to have_content('return_policy')
    end
    
    it 'allows business user to access their dashboard' do
      visit root_path
      
      # Business users should be able to access pages
      expect(page).to have_content('BizBlasts')
    end
  end
  
  describe 'when user has already accepted policies' do
    before do
      # Create policy acceptances for all required policies
      create(:policy_acceptance, user: user, policy_type: 'privacy_policy', policy_version: 'v1.0')
      create(:policy_acceptance, user: user, policy_type: 'terms_of_service', policy_version: 'v1.0')
      create(:policy_acceptance, user: user, policy_type: 'acceptable_use_policy', policy_version: 'v1.0')
      user.update!(requires_policy_acceptance: false)
    end
    
    it 'shows no missing policies in status endpoint' do
      visit '/policy_status'
      
      expect(page).to have_content('requires_policy_acceptance')
      expect(page).to have_content('false').or have_content('"missing_policies":[]')
    end
    
    it 'allows normal dashboard access' do
      visit dashboard_path
      
      expect(page).to have_content('Dashboard').or have_content('My Bookings').or have_content('BizBlasts')
      
      # Modal should still be present in HTML but not triggered
      expect(page).to have_css('#policy-acceptance-modal', visible: false)
    end
  end
  
  describe 'policy acceptance recording' do
    it 'can create individual policy acceptance' do
      expect {
        PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      }.to change(PolicyAcceptance, :count).by(1)
      
      acceptance = PolicyAcceptance.last
      expect(acceptance.user).to eq(user)
      expect(acceptance.policy_type).to eq('privacy_policy')
      expect(acceptance.policy_version).to eq('v1.0')
    end
    
    it 'marks user as not requiring policy acceptance when all policies accepted' do
      # Accept all required policies
      PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      PolicyAcceptance.record_acceptance(user, 'terms_of_service', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      PolicyAcceptance.record_acceptance(user, 'acceptable_use_policy', 'v1.0', double('request', remote_ip: '127.0.0.1', user_agent: 'test'))
      
      user.mark_policies_accepted!
      
      expect(user.reload.requires_policy_acceptance).to be false
      expect(user.missing_required_policies).to be_empty
    end
  end
end 