require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Integrations", type: :request do
  let(:business) { create(:business) }
  let(:business_manager_user) { create(:user, :manager, business: business) }

  before do
    # IMPORTANT: Set the host to the business's subdomain for SubdomainConstraint to work
    host! "#{business.hostname}.lvh.me"
    # Set the current tenant for ActsAsTenant
    ActsAsTenant.current_tenant = business
    sign_in business_manager_user
  end

  after do
    # Reset the current tenant after each test
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      get business_manager_settings_integrations_path
      expect(response).to be_successful
    end

    it "includes Google Business integration UI" do
      get business_manager_settings_integrations_path
      expect(response.body).to include("Google Business Reviews")
      expect(response.body).to include("More Integrations Coming Soon")
    end
  end

  describe "POST /lookup-place-id" do
    let(:valid_google_maps_url) { "https://www.google.com/maps/place/My+Business/@40.7128,-74.0060,17z" }

    context "with valid URL" do
      it "accepts valid google.com URL" do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['job_id']).to be_present
      end

      it "accepts valid google.co.uk URL" do
        url = "https://www.google.co.uk/maps/place/My+Business/@51.5074,-0.1278,17z"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:success)
      end
    end

    context "URL validation (security)" do
      it "rejects http:// URLs (must be HTTPS)" do
        url = "http://www.google.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URL injection attempts (subdomain attack)" do
        url = "https://google.com.evil.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URL injection attempts (path injection)" do
        url = "https://evil.com/google.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URLs without /maps/ in path" do
        url = "https://www.google.com/search?q=My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects empty input" do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: "" }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Please enter a Google Maps URL')
      end

      it "rejects malformed URLs" do
        url = "not-a-valid-url"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end
    end

    context "rate limiting (security)" do
      before do
        # Clear any existing rate limit for this user
        Rails.cache.delete("place_id_extraction:user:#{business_manager_user.id}")
      end

      it "allows up to 5 requests per hour" do
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
          expect(response).to have_http_status(:success)
        end
      end

      it "blocks 6th request within same hour" do
        # Make 5 successful requests
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        end

        # 6th request should be rate limited
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:too_many_requests)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Rate limit exceeded')
        expect(json['error']).to include('5 Place IDs per hour')
      end

      it "resets rate limit after cache expiry" do
        # Make 5 requests
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        end

        # Simulate cache expiry
        Rails.cache.delete("place_id_extraction:user:#{business_manager_user.id}")

        # Should be able to make request again
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:success)
      end
    end
  end
end