# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Subscriptions", type: :request do
  let(:business) { create(:business, tier: 'free', hostname: 'testbiz', subdomain: 'testbiz') }
  let(:premium_business) { create(:business, tier: 'premium', host_type: 'subdomain', hostname: 'premiumtest') }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:premium_manager) { create(:user, :manager, business: premium_business) }

  # Define host for subdomain routing - use hostname for subdomain businesses, subdomain for custom domain businesses in tests
  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }
  let(:premium_host_params) { { host: "#{premium_business.hostname}.lvh.me" } }

  before do
    # Clear any existing tenant
    ActsAsTenant.current_tenant = nil
    
    # Mock Stripe configuration
    allow(Rails.application.credentials).to receive(:stripe).and_return({ 
      secret_key: 'sk_test_xyz', 
      webhook_secret: 'whsec_abc' 
    })
    Stripe.api_key = 'sk_test_xyz'
    
    # Mock environment variables for Stripe price IDs
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_STANDARD_PRICE_ID').and_return('price_standard_test_123')
    allow(ENV).to receive(:[]).with('STRIPE_PREMIUM_PRICE_ID').and_return('price_premium_test_123')
  end

  describe "GET /business_manager/settings/subscriptions" do
    context "when business has no subscription (free tier)" do
      before do
        sign_in manager_user
        ActsAsTenant.current_tenant = business
        get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => host_params[:host] }
      end

      it "shows upgrade options" do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("You're currently on the free plan. Upgrade to unlock more features!")
        expect(response.body).to include("Standard Plan")
        expect(response.body).to include("Premium Plan")
      end

      it "displays domain coverage information for Premium plan" do
        expect(response.body).to include("BizBlasts covers up to $20/year for new domain registration")
        expect(response.body).to include("Custom Domain")
        expect(response.body).to include("Domain Coverage Policy")
      end

      it "shows detailed domain coverage policy" do
        expect(response.body).to include("Domain Coverage Policy")
        expect(response.body).to include("BizBlasts covers up to $20/year for new domain registration")
        expect(response.body).to include("If you already own your domain, you handle domain costs")
        expect(response.body).to include("Domains over $20/year: You obtain your own domain")
      end

      it "includes upgrade buttons" do
        expect(response.body).to include("Upgrade to Standard")
        expect(response.body).to include("Upgrade to Premium")
      end
    end

    context "when business is premium tier" do
      let!(:subscription) { create(:subscription, business: premium_business, plan_name: 'premium', status: 'active') }
      
      before do
        sign_in premium_manager
        ActsAsTenant.current_tenant = premium_business
        get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => premium_host_params[:host] }
      end

      it "shows current subscription details" do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Current Subscription")
        expect(response.body).to include("Business Tier")
      end

      it "includes subscription management button" do
        expect(response.body).to include("Manage Subscription")
      end
    end
  end

  describe "Domain coverage display logic" do
    context "for premium business with domain coverage applied" do
      let!(:premium_business_with_coverage) do
        create(:business, 
          tier: 'premium', 
          host_type: 'subdomain',
          hostname: 'coveragetest',
          subdomain: 'coveragetest',
          domain_coverage_applied: true,
          domain_cost_covered: 15.99,
          domain_renewal_date: 1.year.from_now
        )
      end
      let!(:premium_manager_with_coverage) { create(:user, :manager, business: premium_business_with_coverage) }
      let(:coverage_host_params) { { host: "#{premium_business_with_coverage.hostname}.lvh.me" } }

      before do
        sign_in premium_manager_with_coverage
        ActsAsTenant.current_tenant = premium_business_with_coverage
        get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => coverage_host_params[:host] }
      end

      it "could show domain coverage status (if implemented in view logic)" do
        # This test would verify if domain coverage status is shown in subscription view
        # Currently the subscription view doesn't check for coverage status,
        # but this test is here for future enhancement
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "Responsive design elements" do
    before do
      sign_in manager_user
      ActsAsTenant.current_tenant = business
      get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => host_params[:host] }
    end

    it "includes CSS styling for premium plan highlighting" do
      expect(response.body).to include("border-purple-300")
      expect(response.body).to include("bg-purple-50")
    end

    it "includes proper grid layout classes" do
      expect(response.body).to include("grid grid-cols-1 md:grid-cols-2")
    end
  end

  describe "Premium plan benefits display" do
    before do
      sign_in manager_user
      ActsAsTenant.current_tenant = business
      get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => host_params[:host] }
    end

    it "shows all premium tier benefits" do
      expect(response.body).to include("All Standard tier features")
      expect(response.body).to include("Custom Domain")
      expect(response.body).to include("Priority support")
      expect(response.body).to include("Unlimited staff members")
    end

    it "highlights domain coverage as a key benefit" do
      expect(response.body).to include("Domain Coverage Policy")
      expect(response.body).to include("BizBlasts covers up to $20/year")
    end
  end

  describe "Error handling" do
    context "when not signed in" do
      it "redirects to sign in" do
        get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => host_params[:host] }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when accessing without business context" do
      before do
        sign_in manager_user
        # Don't set tenant
      end

      it "handles missing tenant gracefully" do
        get business_manager_settings_subscription_path, env: { 'HTTP_HOST' => host_params[:host] }
        # The BusinessManager::BaseController automatically sets tenant from subdomain,
        # so this should succeed
        expect(response).to have_http_status(:success)
      end
    end
  end
end 