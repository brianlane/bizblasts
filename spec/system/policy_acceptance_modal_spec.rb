# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Policy Acceptance Modal', type: :system, js: true do
  let(:user) { create(:user, role: :client) }
  let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
  let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true) }
  let!(:aup_policy) { create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true) }
  
  before do
    # Mark user as requiring policy acceptance
    user.update!(requires_policy_acceptance: true)
    login_as(user, scope: :user)
  end
  
  describe 'modal display and blocking' do
    it 'shows the policy acceptance modal on page load' do
      visit root_path
      
      expect(page).to have_css('#policy-acceptance-modal', visible: true)
      expect(page).to have_content('Policy Updates Required')
      expect(page).to have_content('We\'ve updated our policies')
    end
    
    it 'displays all required policies for client users' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        expect(page).to have_content('Privacy Policy')
        expect(page).to have_content('Terms Of Service')
        expect(page).to have_content('Acceptable Use Policy')
        expect(page).not_to have_content('Return Policy') # Not required for clients
      end
    end
    
    it 'prevents modal from being closed without accepting policies' do
      visit root_path
      
      # Try to close modal by clicking background
      find('#policy-acceptance-modal').click
      expect(page).to have_css('#policy-acceptance-modal', visible: true)
      
      # Try to close with Escape key
      page.send_keys(:escape)
      expect(page).to have_css('#policy-acceptance-modal', visible: true)
    end
    
    it 'disables the accept button until all policies are checked' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        accept_button = find('#accept-all-policies')
        expect(accept_button).to be_disabled
        expect(accept_button.text).to include('Accept All (0/')
      end
    end
    
    it 'enables the accept button when all policies are checked' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        # Check all policy checkboxes
        all('.policy-checkbox').each { |checkbox| checkbox.check }
        
        accept_button = find('#accept-all-policies')
        expect(accept_button).not_to be_disabled
        expect(accept_button.text).to eq('Accept All & Continue')
      end
    end
    
    it 'updates button text as policies are checked' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        accept_button = find('#accept-all-policies')
        
        # Check first policy
        first('.policy-checkbox').check
        expect(accept_button.text).to include('Accept All (1/')
        
        # Check second policy
        all('.policy-checkbox')[1].check
        expect(accept_button.text).to include('Accept All (2/')
      end
    end
    
    it 'successfully accepts all policies and closes modal' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        # Check all policies
        all('.policy-checkbox').each { |checkbox| checkbox.check }
        
        # Click accept button
        click_button 'Accept All & Continue'
      end
      
      # Wait for AJAX request to complete and modal to close
      expect(page).not_to have_css('#policy-acceptance-modal', visible: true)
      
      # Verify policy acceptances were recorded
      expect(PolicyAcceptance.where(user: user).count).to eq(3)
      expect(user.reload.requires_policy_acceptance).to be false
    end
    
    it 'shows success message after accepting policies' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        all('.policy-checkbox').each { |checkbox| checkbox.check }
        click_button 'Accept All & Continue'
      end
      
      # Look for success message
      expect(page).to have_content('Policies accepted successfully!')
    end
    
    it 'includes links to read each policy' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        expect(page).to have_link('Read Privacy Policy', href: '/privacypolicy')
        expect(page).to have_link('Read Terms Of Service', href: '/terms')
        expect(page).to have_link('Read Acceptable Use Policy', href: '/acceptableusepolicy')
      end
    end
  end
  
  describe 'business user requirements' do
    let(:business_user) { create(:user, role: :manager) }
    let!(:return_policy) { create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true) }
    
    before do
      business_user.update!(requires_policy_acceptance: true)
      login_as(business_user, scope: :user)
    end
    
    it 'shows return policy for business users' do
      visit root_path
      
      within('#policy-acceptance-modal') do
        expect(page).to have_content('Privacy Policy')
        expect(page).to have_content('Terms Of Service')
        expect(page).to have_content('Acceptable Use Policy')
        expect(page).to have_content('Return Policy')
      end
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
    
    it 'does not show the modal' do
      visit root_path
      
      expect(page).not_to have_css('#policy-acceptance-modal', visible: true)
    end
  end
  
  describe 'error handling' do
    it 'shows error message if acceptance fails' do
      # Mock a server error
      allow_any_instance_of(PolicyAcceptancesController).to receive(:bulk_create).and_raise(StandardError.new('Test error'))
      
      visit root_path
      
      within('#policy-acceptance-modal') do
        all('.policy-checkbox').each { |checkbox| checkbox.check }
        click_button 'Accept All & Continue'
      end
      
      # Should show error alert
      expect(page.driver.browser.switch_to.alert.text).to include('An error occurred')
      page.driver.browser.switch_to.alert.accept
    end
  end
end 