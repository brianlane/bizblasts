# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business::Registrations", type: :request do
  # Use truncation strategy for this spec file to avoid potential transaction issues
  before(:all) do
    DatabaseCleaner.strategy = :truncation
  end

  after(:all) do
    DatabaseCleaner.strategy = :transaction # Reset to default
  end

  before(:each) do
    DatabaseCleaner.clean
    # Mock Stripe API key configuration for all tests
    allow(Rails.application.credentials).to receive(:stripe).and_return({ 
      secret_key: 'sk_test_xyz', 
      webhook_secret: 'whsec_abc' 
    })
    Stripe.api_key = 'sk_test_xyz'
  end

  describe "POST /business" do
    let(:base_user_attributes) do
      {
        first_name: "Test",
        last_name: "Manager",
        email: "manager@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    end

    let(:base_business_attributes) do
      {
        name: "Test Biz",
        industry: Business.industries.keys.sample,
        phone: "1234567890",
        email: "contact@testbiz.com",
        address: "123 Main St",
        city: "Anytown",
        state: "CA",
        zip: "12345",
        description: "A test business"
      }
    end

    let(:free_tier_attrs) { { tier: 'free', hostname: 'test-biz' } }
    let(:standard_tier_subdomain_attrs) { { tier: 'standard', hostname: 'std-biz' } }
    let(:standard_tier_domain_attrs) { { tier: 'standard', hostname: 'std-biz.com' } }
    let(:premium_tier_domain_attrs) { { tier: 'premium', hostname: 'premium-biz.com' } }
    let(:premium_tier_both_attrs) { { tier: 'premium', hostname: 'premium-biz.com' } }

    def build_params(business_attrs)
      { user: base_user_attributes.merge(business_attributes: base_business_attributes.merge(business_attrs)) }
    end

    # Mock Stripe services for paid tiers
    before do
      # Mock StripeService.create_connect_account
      allow(StripeService).to receive(:create_connect_account) do |business|
        mock_account = Stripe::Account.construct_from({
          id: "acct_#{SecureRandom.hex(8)}",
          type: 'express',
          country: 'US',
          email: business.email
        })
        business.update!(stripe_account_id: mock_account.id)
        mock_account
      end

      # Mock StripeService.ensure_stripe_customer_for_business
      allow(StripeService).to receive(:ensure_stripe_customer_for_business) do |business|
        mock_customer = Stripe::Customer.construct_from({
          id: "cus_#{SecureRandom.hex(8)}",
          email: business.email,
          name: business.name
        })
        business.update!(stripe_customer_id: mock_customer.id)
        mock_customer
      end

      # Mock Stripe::Checkout::Session.create for subscription checkout
      allow(Stripe::Checkout::Session).to receive(:create).and_return(
        Stripe::Checkout::Session.construct_from({
          id: "cs_test_#{SecureRandom.hex(8)}",
          url: "https://checkout.stripe.com/pay/cs_test_123"
        })
      )
    end

    shared_examples "successful business sign-up" do |param_builder, expected_tier, expected_hostname, expected_host_type|
      it "creates a new User with manager role and associated Business" do
        params = build_params(send(param_builder))
        expect {
          post business_registration_path, params: params
        }.to change(User, :count).by(1).and change(Business, :count).by(1)

        new_user = User.last
        new_business = Business.last

        expect(new_user.email).to eq(params[:user][:email])
        expect(new_user.manager?).to be true
        expect(new_user.business).to eq(new_business)
        expect(new_user.businesses_as_staff).to include(new_business)
        expect(new_business.staff).to include(new_user)

        expect(new_business.name).to eq(params[:user][:business_attributes][:name])
        expect(new_business.tier).to eq(expected_tier)
        expect(new_business.hostname).to eq(expected_hostname)
        expect(new_business.host_type).to eq(expected_host_type)
      end

      it "redirects to the root path after sign up" do
        params = build_params(send(param_builder))
        post business_registration_path, params: params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.")
      end

      it "does not sign in the user immediately (requires email confirmation)" do
        params = build_params(send(param_builder))
        post business_registration_path, params: params
        expect(controller.current_user).to be_nil
      end
    end

    shared_examples "successful business sign-up with Stripe integration" do |param_builder, expected_tier, expected_hostname, expected_host_type|
      include_examples "successful business sign-up", param_builder, expected_tier, expected_hostname, expected_host_type

      it "creates Stripe Connect account and customer for paid tiers" do
        params = build_params(send(param_builder))
        post business_registration_path, params: params
        
        new_business = Business.last
        expect(StripeService).to have_received(:create_connect_account).with(new_business)
        expect(StripeService).to have_received(:ensure_stripe_customer_for_business).with(new_business)
        expect(new_business.stripe_account_id).to be_present
        expect(new_business.stripe_customer_id).to be_present
      end

      it "handles Stripe Connect account creation failure gracefully" do
        allow(StripeService).to receive(:create_connect_account).and_raise(Stripe::APIError.new("Stripe error"))
        
        params = build_params(send(param_builder))
        expect {
          post business_registration_path, params: params
        }.to change(User, :count).by(1).and change(Business, :count).by(1)
        
        # Business should still be created even if Stripe fails
        new_business = Business.last
        expect(new_business.stripe_account_id).to be_nil
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.")
      end

      it "handles Stripe customer creation failure gracefully" do
        allow(StripeService).to receive(:ensure_stripe_customer_for_business).and_raise(Stripe::APIError.new("Customer creation failed"))
        
        params = build_params(send(param_builder))
        expect {
          post business_registration_path, params: params
        }.to change(User, :count).by(1).and change(Business, :count).by(1)
        
        # Business should still be created even if Stripe customer creation fails
        new_business = Business.last
        expect(new_business.stripe_customer_id).to be_nil
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.")
      end
    end

    context "with valid parameters (Free Tier)" do
      include_examples "successful business sign-up", :free_tier_attrs, 'free', 'test-biz', 'subdomain'

      it "does not create Stripe accounts for free tier" do
        params = build_params(free_tier_attrs)
        post business_registration_path, params: params
        
        expect(StripeService).not_to have_received(:create_connect_account)
        expect(StripeService).not_to have_received(:ensure_stripe_customer_for_business)
        
        new_business = Business.last
        expect(new_business.stripe_account_id).to be_nil
        expect(new_business.stripe_customer_id).to be_nil
      end
    end

    context "with valid parameters (Standard Tier - Subdomain)" do
      include_examples "successful business sign-up with Stripe integration", :standard_tier_subdomain_attrs, 'standard', 'std-biz', 'subdomain'
    end

    context "with valid parameters (Standard Tier - Domain)" do
      include_examples "successful business sign-up with Stripe integration", :standard_tier_domain_attrs, 'standard', 'std-biz.com', 'custom_domain'
    end

    context "with valid parameters (Premium Tier - Domain)" do
      include_examples "successful business sign-up with Stripe integration", :premium_tier_domain_attrs, 'premium', 'premium-biz.com', 'custom_domain'
    end

    context "with valid parameters (Premium Tier - Both - Domain Takes Precedence)" do
      include_examples "successful business sign-up with Stripe integration", :premium_tier_both_attrs, 'premium', 'premium-biz.com', 'custom_domain'
    end

    context "with invalid parameters" do
      it "does not create User, Business or StaffMember if user validation fails" do
        params = build_params(free_tier_attrs)
        params[:user][:email] = 'invalid' # Invalid user email
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count, StaffMember.count] }
      end

      it "does not create User, Business or StaffMember if business validation fails" do
        params = build_params(free_tier_attrs)
        params[:user][:business_attributes][:name] = '' # Invalid business name
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count, StaffMember.count] }
      end

      it "re-renders the 'new' template with errors" do
        params = build_params(free_tier_attrs)
        params[:user][:business_attributes][:name] = '' # Invalid business name
        post business_registration_path, params: params
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Name can&#39;t be blank/m)
      end

      it "does not call Stripe services when validation fails" do
        params = build_params(standard_tier_subdomain_attrs)
        params[:user][:business_attributes][:name] = '' # Invalid business name
        
        post business_registration_path, params: params
        
        expect(StripeService).not_to have_received(:create_connect_account)
        expect(StripeService).not_to have_received(:ensure_stripe_customer_for_business)
      end
    end

    context "when tier requires subdomain host_type (Free)" do
      it "fails if hostname is missing in params" do
        params = build_params(free_tier_attrs)
        params[:user][:business_attributes][:hostname] = ''
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Hostname can&#39;t be blank/m)
      end
      
      it "fails if a custom domain hostname is provided" do
        params = build_params(free_tier_attrs)
        params[:user][:business_attributes][:hostname] = 'my-domain.com'
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Host type must be &#39;subdomain&#39; for the Free tier/m)
      end
    end

    context "when tier allows either host_type (Standard/Premium)" do
      it "fails if hostname is missing in params" do
        params = build_params(standard_tier_subdomain_attrs)
        params[:user][:business_attributes].delete(:hostname)
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Hostname can&#39;t be blank/m)
      end
    end

    context "uniqueness constraints" do
      let!(:existing_business_subdomain) { create(:business, hostname: 'taken-sub', host_type: 'subdomain') }
      let!(:existing_business_domain) { create(:business, hostname: 'taken.com', host_type: 'custom_domain') }
      let!(:other_business) { create(:business, hostname: 'another', host_type: 'subdomain') } # Needed for manager user
      let!(:existing_manager) { create(:user, role: :manager, email: 'manager@example.com', business: other_business) }
      let!(:existing_client) { create(:user, role: :client, email: 'client@example.com') }

      it "fails if manager email is taken by another manager/staff" do
        params = build_params(free_tier_attrs)
        params[:user][:email] = 'manager@example.com'
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Email has already been taken/m)
        expect(response.body).not_to match(/Email has already been taken by another business owner or staff member/m)
      end

      it "fails if manager email is taken only by a client" do
        # Construct params with nested business_attributes and the client's email
        user_attrs = attributes_for(:user, email: existing_client.email)
        business_attrs = attributes_for(:business, hostname: 'unique-client-test-host') # Ensure unique hostname
        params = {
          user: user_attrs.merge(role: :manager, business_attributes: business_attrs)
        }
        # Expect counts NOT to change due to global uniqueness
        expect {
          post business_registration_path, params: params
        }.to_not change(User, :count)
        expect {
          # Need to re-post or check business count in a separate block
          post business_registration_path, params: params
        }.to_not change(Business, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Email has already been taken")
      end

      it "fails if hostname (subdomain type) is taken" do
        params = build_params(standard_tier_subdomain_attrs)
        params[:user][:business_attributes][:hostname] = 'taken-sub'
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Hostname has already been taken/m)
      end

      it "fails if hostname (custom domain type) is taken" do
        params = build_params(standard_tier_domain_attrs)
        params[:user][:business_attributes][:hostname] = 'taken.com'
        expect {
          post business_registration_path, params: params
        }.not_to change { [User.count, Business.count] }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/id="error_explanation".*Hostname has already been taken/m)
      end
    end

    context "Stripe integration edge cases" do
      it "handles partial Stripe setup gracefully" do
        # Simulate Connect account creation succeeding but customer creation failing
        allow(StripeService).to receive(:ensure_stripe_customer_for_business).and_raise(Stripe::APIError.new("Customer error"))
        
        params = build_params(standard_tier_subdomain_attrs)
        expect {
          post business_registration_path, params: params
        }.to change(User, :count).by(1).and change(Business, :count).by(1)
        
        new_business = Business.last
        expect(new_business.stripe_account_id).to be_present # Connect account was created
        expect(new_business.stripe_customer_id).to be_nil # Customer creation failed
        expect(response).to redirect_to(root_path)
      end

      it "logs Stripe errors appropriately" do
        allow(Rails.logger).to receive(:error)
        allow(StripeService).to receive(:create_connect_account).and_raise(Stripe::APIError.new("Connect error"))
        
        params = build_params(premium_tier_domain_attrs)
        post business_registration_path, params: params
        
        expect(Rails.logger).to have_received(:error).with(/Stripe Connect account creation failed/)
      end
    end
  end
end 