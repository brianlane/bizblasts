# frozen_string_literal: true

require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe "BusinessManager::Settings::Subscriptions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business, stripe_customer_id: "cus_#{SecureRandom.hex(8)}") }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }
  let(:client_user) { create(:user, :client) }
  let!(:subscription) { create(:subscription, business: business, stripe_subscription_id: "sub_#{SecureRandom.hex(8)}") }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    # Mock Stripe API Key for controller callbacks
    allow(Rails.application.credentials).to receive(:stripe).and_return({ secret_key: 'sk_test_xyz', webhook_secret: 'whsec_abc' })
    # Set Stripe API key for all tests
    Stripe.api_key = 'sk_test_xyz'
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /manage/settings/subscription" do
    subject { get business_manager_settings_subscription_path }

    context "when authenticated as a business manager" do
      before { sign_in manager_user }

      it "renders a successful response" do
        subject
        expect(response).to be_successful
        expect(response).to render_template(:show)
      end

      it "assigns the business and subscription" do
        subject
        expect(assigns(:business)).to eq(business)
        expect(assigns(:subscription)).to eq(subscription)
      end

      context "when business has no subscription" do
        let!(:subscription) { nil }
        before { business.subscription&.destroy } # Ensure no subscription exists

        it "renders successfully and assigns a new subscription object" do
          subject
          expect(response).to be_successful
          expect(assigns(:subscription)).to be_nil # Controller sets @subscription directly via business.subscription
        end
      end
    end

    context "when authenticated as staff" do
      before { sign_in staff_user }
      it "redirects with an alert" do
        subject
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "when not authenticated" do
      it "redirects to the sign in page" do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST /manage/settings/subscription/checkout" do
    let(:stripe_price_id) { "price_#{SecureRandom.hex(8)}" }
    subject { post business_manager_settings_subscription_checkout_path, params: { price_id: stripe_price_id } }

    before do
      # Mock Stripe::Checkout::Session.create
      allow(Stripe::Checkout::Session).to receive(:create).and_return(
        Stripe::Checkout::Session.construct_from(
          {
            id: "cs_test_#{SecureRandom.hex(8)}",
            url: "https://checkout.stripe.com/pay/cs_test_123"
          }
        )
      )
    end

    context "when authenticated as a business manager" do
      before { sign_in manager_user }

      it "redirects to Stripe checkout" do
        subject
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(
            payment_method_types: ['card'],
            line_items: [hash_including(price: stripe_price_id, quantity: 1)],
            mode: 'subscription',
            customer: business.stripe_customer_id,
            client_reference_id: business.id
          )
        )
        expect(response).to redirect_to("https://checkout.stripe.com/pay/cs_test_123")
      end

      context "when Stripe API call fails" do
        before do
          allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::APIError.new("Stripe error"))
        end

        it "redirects to subscription page with an alert" do
          subject
          expect(response).to redirect_to(business_manager_settings_subscription_path)
          expect(flash[:alert]).to match(/Could not connect to Stripe: Stripe error/)
        end
      end
    end

    context "when authenticated as staff" do
      before { sign_in staff_user }
      it "redirects with an alert" do
        subject
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /manage/settings/subscription/portal" do
    subject { post business_manager_settings_subscription_portal_path }

    before do
      # Mock Stripe::BillingPortal::Session.create
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(
        Stripe::BillingPortal::Session.construct_from(
          {
            id: "pts_test_#{SecureRandom.hex(8)}",
            url: "https://billing.stripe.com/session/pts_test_123"
          }
        )
      )
    end

    context "when authenticated as a business manager" do
      before { sign_in manager_user }

      it "redirects to Stripe customer portal" do
        subject
        expect(Stripe::BillingPortal::Session).to have_received(:create).with(
          hash_including(
            customer: business.stripe_customer_id,
            return_url: business_manager_settings_subscription_url
          )
        )
        expect(response).to redirect_to("https://billing.stripe.com/session/pts_test_123")
      end

      context "when Stripe API call fails" do
        before do
          allow(Stripe::BillingPortal::Session).to receive(:create).and_raise(Stripe::APIError.new("Stripe portal error"))
        end

        it "redirects to subscription page with an alert" do
          subject
          expect(response).to redirect_to(business_manager_settings_subscription_path)
          expect(flash[:alert]).to match(/Could not connect to Stripe: Stripe portal error/)
        end
      end
    end

    context "when authenticated as staff" do
      before { sign_in staff_user }
      it "redirects with an alert" do
        subject
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /manage/settings/stripe_events" do
    let(:webhook_secret) { 'whsec_abc' }
    let(:payload) { { id: "evt_#{SecureRandom.hex(8)}", type: "test.event" }.to_json }
    let(:timestamp) { Time.now.to_i }
    let(:scheme) { 'v1' } # Default scheme
    let(:signature) do
      # Manual signature generation based on Stripe's internal logic
      signed_payload = "#{timestamp}.#{payload}"
      expected_signature = OpenSSL::HMAC.hexdigest('sha256', webhook_secret, signed_payload)
      "t=#{timestamp},#{scheme}=#{expected_signature}"
    end

    context "with valid signature and payload" do
      it "returns http success" do
        # Mock Stripe::Webhook.construct_event to return a proper event object
        expected_event = Stripe::Event.construct_from(JSON.parse(payload))
        
        allow(Stripe::Webhook).to receive(:construct_event).and_return(expected_event)

        # Use raw post to ensure the payload is sent correctly
        post business_manager_settings_stripe_events_path, 
             headers: { 'HTTP_STRIPE_SIGNATURE' => signature, 'CONTENT_TYPE' => 'application/json' },
             params: payload,
             as: :json
             
        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid signature" do
      let(:invalid_signature_header) { "t=#{timestamp},#{scheme}=bad_signature_value" }
      
      it "returns http bad_request" do
        # Make sure the error is raised as expected
        allow(Stripe::Webhook).to receive(:construct_event)
          .and_raise(Stripe::SignatureVerificationError.new('Invalid signature', invalid_signature_header))

        post business_manager_settings_stripe_events_path, 
             headers: { 'HTTP_STRIPE_SIGNATURE' => invalid_signature_header, 'CONTENT_TYPE' => 'application/json' },
             params: payload,
             as: :json
             
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Signature verification failed')
      end
    end

    context "with invalid payload (JSON error)" do
      let(:non_json_payload) { "not_json" }
      # Need a signature for this non_json_payload
      let(:signature_for_non_json) do
        signed_payload = "#{timestamp}.#{non_json_payload}"
        expected_signature = OpenSSL::HMAC.hexdigest('sha256', webhook_secret, signed_payload)
        "t=#{timestamp},#{scheme}=#{expected_signature}"
      end
      
      it "returns http bad_request" do
        # Make it trigger a JSON::ParserError
        allow(Stripe::Webhook).to receive(:construct_event)
          .and_raise(JSON::ParserError.new("Invalid JSON"))

        post business_manager_settings_stripe_events_path, 
             headers: { 'HTTP_STRIPE_SIGNATURE' => signature_for_non_json, 'CONTENT_TYPE' => 'text/plain' },
             params: non_json_payload
             
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Invalid payload')
      end
    end

    context "when handling 'checkout.session.completed' event" do
      let(:checkout_session_id) { "cs_#{SecureRandom.hex(8)}" }
      let(:stripe_subscription_id) { "sub_#{SecureRandom.hex(8)}" }
      let(:event_payload) do
        {
          id: "evt_#{SecureRandom.hex(8)}",
          type: "checkout.session.completed",
          data: {
            object: {
              id: checkout_session_id,
              client_reference_id: business.id.to_s,
              subscription: stripe_subscription_id,
              # other necessary fields
            }
          }
        }
      end
      let(:payload) { event_payload.to_json }
      let(:stripe_sub_object) do # Mocked Stripe::Subscription object
        Stripe::Subscription.construct_from({
          id: stripe_subscription_id,
          items: { data: [{ price: { lookup_key: 'basic_plan', product: 'prod_basic' } }] },
          status: 'active',
          current_period_end: Time.now.to_i + (30 * 24 * 60 * 60),
          customer: business.stripe_customer_id
        })
      end

      before do
        # Mock Stripe::Webhook.construct_event to return the checkout session completed event
        allow(Stripe::Webhook).to receive(:construct_event)
          .and_return(Stripe::Event.construct_from(event_payload))
          
        # Mock the Stripe::Subscription.retrieve call
        allow(Stripe::Subscription).to receive(:retrieve).with(stripe_subscription_id).and_return(stripe_sub_object)
        business.subscription&.destroy # Ensure no pre-existing subscription for this test
      end

      it "creates a new subscription record" do
        expect {
          post business_manager_settings_stripe_events_path, 
               headers: { 'HTTP_STRIPE_SIGNATURE' => signature, 'CONTENT_TYPE' => 'application/json' },
               params: payload,
               as: :json
        }.to change(Subscription, :count).by(1)
        
        new_sub = business.reload.subscription
        expect(new_sub).not_to be_nil
        expect(new_sub.stripe_subscription_id).to eq(stripe_subscription_id)
        expect(new_sub.plan_name).to eq('basic_plan')
        expect(new_sub.status).to eq('active')
        expect(response).to have_http_status(:ok)
      end
    end
  end
end 