# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Security', type: :request do
  let!(:business1) { create(:business, hostname: 'business1') }
  let!(:business2) { create(:business, hostname: 'business2') }
  let!(:api_key) { ENV['API_KEY'] || 'demo_api_key_for_testing' }

  describe 'GET /api/v1/businesses' do
    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/businesses'
        expect(response).to have_http_status(:unauthorized)
        expect(json_response['error']).to eq('API authentication required')
      end
    end

    context 'with valid API key' do
      it 'returns limited business data' do
        get '/api/v1/businesses', headers: { 'X-API-Key' => api_key }
        expect(response).to have_http_status(:ok)
        
        businesses = json_response['businesses']
        expect(businesses).to be_an(Array)
        expect(businesses.length).to be <= 20
        
        # Verify only safe data is exposed
        business = businesses.first
        expect(business.keys).to match_array(%w[id name hostname industry location website_url])
        expect(business['location'].keys).to match_array(%w[city state])
        expect(business).not_to have_key('email')
        expect(business).not_to have_key('phone')
        expect(business).not_to have_key('address')
      end
    end

    context 'with invalid API key' do
      it 'returns unauthorized' do
        get '/api/v1/businesses', headers: { 'X-API-Key' => 'invalid_key' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/businesses/:id' do
    context 'without API key' do
      it 'returns unauthorized' do
        get "/api/v1/businesses/#{business1.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid API key' do
      it 'returns sanitized business details' do
        get "/api/v1/businesses/#{business1.id}", headers: { 'X-API-Key' => api_key }
        expect(response).to have_http_status(:ok)
        
        business = json_response['business']
        expect(business).to be_present
        expect(business).not_to have_key('email')
        expect(business).not_to have_key('phone')
        expect(business['location']).not_to have_key('address')
        expect(business['location']).not_to have_key('zip')
        
        # Verify services don't include prices
        if business['services'].present?
          service = business['services'].first
          expect(service).not_to have_key('price')
        end
        
        # Verify products don't include prices
        if business['products'].present?
          product = business['products'].first
          expect(product).not_to have_key('price')
        end
      end
    end
  end

  describe 'Rate limiting' do
    it 'enforces rate limits' do
      # Make 101 requests to exceed limit
      101.times do |i|
        get '/api/v1/businesses/categories'
        if i < 100
          expect(response).to have_http_status(:ok)
        else
          expect(response).to have_http_status(:too_many_requests)
          expect(json_response['error']).to eq('Rate limit exceeded')
          break
        end
      end
    end
  end

  describe 'Public endpoints' do
    it 'allows access to categories without API key' do
      get '/api/v1/businesses/categories'
      expect(response).to have_http_status(:ok)
      expect(json_response).to have_key('service_categories')
    end

    it 'allows access to ai_summary without API key' do
      get '/api/v1/businesses/ai_summary'
      expect(response).to have_http_status(:ok)
      expect(json_response).to have_key('platform')
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end