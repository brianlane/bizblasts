# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Registration", type: :system do
  # Use truncation strategy for system tests to avoid transaction issues
  before(:all) do
    DatabaseCleaner.strategy = :truncation
  end

  after(:all) do
    DatabaseCleaner.strategy = :transaction # Reset to default
  end

  before(:each) do
    DatabaseCleaner.clean
    
    # Create required policy versions for business registration
    create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true)
    
    # Business registration is on the main domain (no subdomain)
    switch_to_main_domain
    
    # Mock Stripe API key configuration
    allow(Rails.application.credentials).to receive(:stripe).and_return({ 
      secret_key: 'sk_test_xyz', 
      webhook_secret: 'whsec_abc' 
    })
    Stripe.api_key = 'sk_test_xyz'
    
    # Mock Stripe services - these should not make real API calls
    allow(StripeService).to receive(:create_connect_account) do |business|
      # Simulate successful account creation without real API call
      account_id = "acct_#{SecureRandom.hex(8)}"
      business.update!(stripe_account_id: account_id)
      # Return a mock account object
      double('Stripe::Account', id: account_id, type: 'express', country: 'US', email: business.email)
    end

    allow(StripeService).to receive(:ensure_stripe_customer_for_business) do |business|
      # Simulate successful customer creation without real API call
      customer_id = "cus_#{SecureRandom.hex(8)}"
      business.update!(stripe_customer_id: customer_id)
      # Return a mock customer object
      double('Stripe::Customer', id: customer_id, email: business.email, name: business.name)
    end
    
    # Mock any other Stripe calls that might be triggered
    allow(Stripe::Account).to receive(:create).and_return(
      double('Stripe::Account', id: "acct_mock_#{SecureRandom.hex(8)}")
    )
    
    allow(Stripe::Customer).to receive(:create).and_return(
      double('Stripe::Customer', id: "cus_mock_#{SecureRandom.hex(8)}")
    )
    
    # Mock Stripe checkout session creation for subscription
    allow(Stripe::Checkout::Session).to receive(:create).and_return(
      double('Stripe::Checkout::Session', 
        id: "cs_test_#{SecureRandom.hex(8)}", 
        url: "https://checkout.stripe.com/pay/cs_subscription_123"
      )
    )
    
    # Mock environment variables for Stripe price IDs
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_STANDARD_PRICE_ID').and_return('price_standard_test_123')
    allow(ENV).to receive(:[]).with('STRIPE_PREMIUM_PRICE_ID').and_return('price_premium_test_123')
  end

  describe "Plan selection interface" do
    it "displays subscription plan tiles" do
      visit new_business_registration_path
      
      expect(page).to have_content("Choose Your Monthly Plan")
      expect(page).to have_content("Free Plan")
      expect(page).to have_content("$0/month")
      expect(page).to have_content("Standard Plan")
      expect(page).to have_content("$49/month")
      expect(page).to have_content("Premium Plan")
      expect(page).to have_content("$99/month")
    end

    it "shows plan features" do
      visit new_business_registration_path
      
      # Free plan features - use more specific selector
      within('.subscription-plan[data-tier="free"]') do
        expect(page).to have_content("Basic features")
        expect(page).to have_content("BizBlasts subdomain")
        expect(page).to have_content("5% payment fee")
        expect(page).to have_content("Essential tools")
      end
      
      # Standard plan features
      within('.subscription-plan[data-tier="standard"]') do
        expect(page).to have_content("Text Reminders")
        expect(page).to have_content("Customizable pages")
        expect(page).to have_content("Calendar Integrations")
        expect(page).to have_content("Advanced tools")
      end
      
      # Premium plan features
      within('.subscription-plan[data-tier="premium"]') do
        expect(page).to have_content("All features")
        expect(page).to have_content("Lower fees")
        expect(page).to have_content("Multi-location support")
        expect(page).to have_content("Remove BizBlasts branding")
        expect(page).to have_content("Custom domain")
      end
    end

    it "shows domain coverage information for Premium plan" do
      visit new_business_registration_path
      
      # Premium plan should show custom domain feature (visible by default)
      within('.subscription-plan[data-tier="premium"]') do
        expect(page).to have_content("Custom domain")
      end
    end

    it "displays domain coverage details when Premium is selected", js: true do
      visit new_business_registration_path
      
      # Click on Premium plan
      within('.subscription-plan[data-tier="premium"]') do
        click_button "Select Premium"
      end
      
      # Should show domain coverage information in description
      expect(page).to have_content("Domain Coverage Included")
      expect(page).to have_content("BizBlasts covers up to $20/year for new domain registration")
      expect(page).to have_content("If you already own your domain, you handle domain costs")
      expect(page).to have_content("Our team manages all technical setup and verification")
    end

    it "shows domain coverage policy in hostname help text for Premium", js: true do
      visit new_business_registration_path
      
      # Click on Premium plan
      within('.subscription-plan[data-tier="premium"]') do
        click_button "Select Premium"
      end
      
      # Should show domain coverage info in help text
      expect(page).to have_content("Domain Coverage: BizBlasts covers up to $20/year for new domains")
      expect(page).to have_content("For domains over $20/year, we'll contact you with alternatives")
    end

    it "has selection buttons for each plan" do
      visit new_business_registration_path
      
      # Free plan is selected by default, so button text changes to "✓ Selected"
      expect(page).to have_button("✓ Selected")
      expect(page).to have_button("Select Standard")
      expect(page).to have_button("Select Premium")
    end

    it "allows plan selection via JavaScript", js: true do
      visit new_business_registration_path
      
      # Click on Standard plan
      within('.subscription-plan[data-tier="standard"]') do
        click_button "Select Standard"
      end
      
      # Wait for JavaScript to update the hidden field
      expect(page).to have_field("selected_tier", with: "standard", type: :hidden)
      
      # Check that the hostname field becomes visible
      expect(page).to have_field("user_business_attributes_hostname", visible: true)
    end
  end

  describe "Form submission" do
    it "successfully creates a business with free tier" do
      visit new_business_registration_path
      
      # Fill in owner information
      fill_in "First name", with: "John"
      fill_in "Last name", with: "Doe"
      fill_in "Email", with: "john@example.com"
      fill_in "Password", with: "password123"
      fill_in "Password confirmation", with: "password123"
      
      # Fill in business information
      fill_in "Business Name", with: "Test Business"
      select "Other", from: "Industry"
      fill_in "Business Phone", with: "555-123-4567"
      fill_in "Business Contact Email", with: "contact@testbiz.com"
      fill_in "Address", with: "123 Main St"
      fill_in "City", with: "Anytown"
      fill_in "State", with: "CA"
      fill_in "Zip", with: "12345"
      fill_in "Description", with: "A test business"
      
      # Free plan should be selected by default, which makes hostname field visible
      expect(page).to have_field("selected_tier", with: "free", type: :hidden)
      
      # Wait for hostname field to be visible and fill it
      expect(page).to have_field("user_business_attributes_hostname", visible: true)
      fill_in "user_business_attributes_hostname", with: "testbiz"
      
      # Accept all required policies for business users
      check "policy_acceptances_terms_of_service"
      check "policy_acceptances_privacy_policy"
      check "policy_acceptances_acceptable_use_policy"
      check "policy_acceptances_return_policy"
      
      # In system test environment, paid tiers create immediately (not Stripe redirect)
      expect {
        click_button "Create Business Account"
      }.to change(Business, :count).by(1).and change(User, :count).by(1)
      
      # Should redirect to root path in test environment
      expect(page).to have_current_path(root_path)
      expect(page).to have_content("A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.")
      
      # Verify business was created with correct attributes
      business = Business.last
      expect(business.tier).to eq("free")
      expect(business.hostname).to eq("testbiz")
      expect(business.host_type).to eq("subdomain")
      expect(business.stripe_account_id).to be_nil
      expect(business.stripe_customer_id).to be_nil
    end

    it "successfully creates a business with standard tier and sets up Stripe", js: true do
      visit new_business_registration_path
      
      # Fill in owner information
      fill_in "First name", with: "Jane"
      fill_in "Last name", with: "Smith"
      fill_in "Email", with: "jane@example.com"
      fill_in "Password", with: "password123"
      fill_in "Password confirmation", with: "password123"
      
      # Fill in business information
      fill_in "Business Name", with: "Standard Business"
      select "Other", from: "Industry"
      fill_in "Business Phone", with: "555-987-6543"
      fill_in "Business Contact Email", with: "contact@standardbiz.com"
      fill_in "Address", with: "456 Oak Ave"
      fill_in "City", with: "Somewhere"
      fill_in "State", with: "NY"
      fill_in "Zip", with: "54321"
      fill_in "Description", with: "A standard business"
      
      # Select standard plan
      within('.subscription-plan[data-tier="standard"]') do
        click_button "Select Standard"
      end
      
      # Wait for JavaScript to update and hostname field to be visible
      expect(page).to have_field("selected_tier", with: "standard", type: :hidden)
      expect(page).to have_field("user_business_attributes_hostname", visible: true)
      fill_in "user_business_attributes_hostname", with: "standardbiz"
      
      # Accept all required policies for business users
      check "policy_acceptances_terms_of_service"
      check "policy_acceptances_privacy_policy"
      check "policy_acceptances_acceptable_use_policy"
      check "policy_acceptances_return_policy"
      
      # For paid tiers, business and user should NOT be created immediately
      # They will be created after successful Stripe payment via webhook
      expect {
        click_button "Create Business Account"
      }.to change(Business, :count).by(0).and change(User, :count).by(0)
      
      # Should redirect to Stripe checkout for paid tiers
      expect(current_url).to eq("https://checkout.stripe.com/pay/cs_subscription_123")
      
      # Verify Stripe checkout session was created with registration data in metadata
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          mode: 'subscription',
          metadata: hash_including(
            registration_type: 'business'
          )
        )
      )
    end
  end

  describe "Error handling" do
    it "shows validation errors when required fields are missing" do
      visit new_business_registration_path
      
      click_button "Create Business Account"
      
      # Check for validation errors - could be in different formats
      expect(page).to have_content("can't be blank").or have_content("errors prohibited").or have_content("required")
      expect(page).to have_current_path(new_business_registration_path)
    end

    it "handles Stripe Connect errors gracefully for paid tiers", js: true do
      # Note: For paid tiers that redirect to Stripe checkout, Stripe Connect account creation
      # happens after successful payment, not during initial registration
      allow(StripeService).to receive(:create_connect_account).and_raise(Stripe::APIError.new("Stripe error"))
      
      visit new_business_registration_path
      
      # Fill in all required fields
      fill_in "First name", with: "Test"
      fill_in "Last name", with: "User"
      fill_in "Email", with: "test@example.com"
      fill_in "Password", with: "password123"
      fill_in "Password confirmation", with: "password123"
      fill_in "Business Name", with: "Test Business"
      select "Other", from: "Industry"
      fill_in "Business Phone", with: "555-123-4567"
      fill_in "Business Contact Email", with: "contact@test.com"
      fill_in "Address", with: "123 Test St"
      fill_in "City", with: "Test City"
      fill_in "State", with: "CA"
      fill_in "Zip", with: "12345"
      fill_in "Description", with: "A test business"
      
      # Select premium plan
      within('.subscription-plan[data-tier="premium"]') do
        click_button "Select Premium"
      end
      
      # Wait for JavaScript and fill hostname
      expect(page).to have_field("selected_tier", with: "premium", type: :hidden)
      expect(page).to have_field("user_business_attributes_hostname", visible: true)
      fill_in "user_business_attributes_hostname", with: "testbiz"
      
      # Accept all required policies
      check "policy_acceptances_terms_of_service"
      check "policy_acceptances_privacy_policy"
      check "policy_acceptances_acceptable_use_policy"
      check "policy_acceptances_return_policy"
      
      # For paid tiers, business and user should NOT be created immediately
      # They will be created after successful Stripe payment via webhook
      # Stripe Connect errors don't affect the initial registration flow
      expect {
        click_button "Create Business Account"
      }.to change(Business, :count).by(0).and change(User, :count).by(0)
      
      # Should still redirect to Stripe checkout (Connect errors happen later)
      expect(current_url).to eq("https://checkout.stripe.com/pay/cs_subscription_123")
      
      # Verify Stripe checkout session was created with registration data
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          mode: 'subscription',
          metadata: hash_including(
            registration_type: 'business'
          )
        )
      )
    end
    
    it "handles Stripe checkout errors gracefully for paid tiers", js: true do
      allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::APIError.new("Checkout error"))
      
      visit new_business_registration_path
      
      # Fill in all required fields
      fill_in "First name", with: "Test"
      fill_in "Last name", with: "User"
      fill_in "Email", with: "test2@example.com"
      fill_in "Password", with: "password123"
      fill_in "Password confirmation", with: "password123"
      fill_in "Business Name", with: "Test Business 2"
      select "Other", from: "Industry"
      fill_in "Business Phone", with: "555-123-4567"
      fill_in "Business Contact Email", with: "contact@test2.com"
      fill_in "Address", with: "123 Test St"
      fill_in "City", with: "Test City"
      fill_in "State", with: "CA"
      fill_in "Zip", with: "12345"
      fill_in "Description", with: "A test business"
      
      # Select premium plan
      within('.subscription-plan[data-tier="premium"]') do
        click_button "Select Premium"
      end
      
      # Wait for JavaScript and fill hostname
      expect(page).to have_field("selected_tier", with: "premium", type: :hidden)
      expect(page).to have_field("user_business_attributes_hostname", visible: true)
      fill_in "user_business_attributes_hostname", with: "testbiz2"
      
      # Accept all required policies
      check "policy_acceptances_terms_of_service"
      check "policy_acceptances_privacy_policy"
      check "policy_acceptances_acceptable_use_policy"
      check "policy_acceptances_return_policy"
      
      # When Stripe checkout fails, no business/user should be created
      expect {
        click_button "Create Business Account"
      }.to change(Business, :count).by(0).and change(User, :count).by(0)
      
      # Should redirect back to registration form with error message when Stripe checkout fails
      expect(page).to have_current_path(new_business_registration_path)
      expect(page).to have_content("Could not connect to Stripe for subscription setup: Checkout error")
    end
  end
end 