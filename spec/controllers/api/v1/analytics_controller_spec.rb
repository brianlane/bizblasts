# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AnalyticsController, type: :request do
  let(:business) { create(:business, subdomain: 'testbiz') }
  
  describe 'POST /api/v1/analytics/track' do
    let(:valid_events) do
      [
        {
          type: 'page_view',
          timestamp: Time.current.iso8601,
          session_id: SecureRandom.uuid,
          visitor_fingerprint: SecureRandom.hex(16),
          business_id: business.id,
          data: {
            page_path: '/services',
            page_type: 'services',
            device_type: 'desktop',
            browser: 'Chrome'
          }
        }
      ]
    end

    context 'with valid events' do
      it 'queues events for processing' do
        expect {
          post '/api/v1/analytics/track',
               params: { events: valid_events }.to_json,
               headers: { 
                 'Content-Type' => 'application/json',
                 'Host' => 'testbiz.lvh.me'
               }
        }.to have_enqueued_job(AnalyticsIngestionJob)

        expect(response).to have_http_status(:accepted)
        expect(JSON.parse(response.body)['status']).to eq('queued')
      end
    end

    context 'with DNT header set' do
      it 'skips tracking' do
        expect {
          post '/api/v1/analytics/track',
               params: { events: valid_events }.to_json,
               headers: { 
                 'Content-Type' => 'application/json',
                 'Host' => 'testbiz.lvh.me',
                 'DNT' => '1'
               }
        }.not_to have_enqueued_job(AnalyticsIngestionJob)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('skipped')
      end
    end

    context 'with bot user agent' do
      it 'skips tracking' do
        expect {
          post '/api/v1/analytics/track',
               params: { events: valid_events }.to_json,
               headers: { 
                 'Content-Type' => 'application/json',
                 'Host' => 'testbiz.lvh.me',
                 'User-Agent' => 'Googlebot/2.1'
               }
        }.not_to have_enqueued_job(AnalyticsIngestionJob)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid events parameter' do
      it 'returns bad request' do
        post '/api/v1/analytics/track',
             params: { events: 'not_an_array' }.to_json,
             headers: { 
               'Content-Type' => 'application/json',
               'Host' => 'testbiz.lvh.me'
             }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'rate limiting' do
      it 'returns too many requests after limit exceeded' do
        # Simulate exceeding rate limit
        cache_key = "analytics_rate_limit:127.0.0.1"
        Rails.cache.write(cache_key, 100, expires_in: 1.minute)

        post '/api/v1/analytics/track',
             params: { events: valid_events }.to_json,
             headers: { 
               'Content-Type' => 'application/json',
               'Host' => 'testbiz.lvh.me'
             }

        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end

