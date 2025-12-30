# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Analytics Tracking Flow', type: :request do
  let(:business) { create(:business) }
  let(:session_id) { SecureRandom.uuid }
  let(:visitor_fingerprint) { SecureRandom.hex(16) }

  before do
    host! "#{business.subdomain}.lvh.me"
  end

  describe 'Page View -> Click Event -> Conversion Flow' do
    it 'tracks complete user journey end-to-end' do
      # Step 1: Track page view
      page_view_event = {
        events: [{
          type: 'page_view',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: {
            page_path: '/services',
            page_type: 'services',
            page_title: 'Our Services',
            device_type: 'desktop',
            browser: 'Chrome',
            os: 'Windows'
          }
        }]
      }

      expect {
        post api_v1_analytics_track_path, params: page_view_event
      }.to have_enqueued_job(AnalyticsIngestionJob)

      expect(response).to have_http_status(:accepted)
      result = JSON.parse(response.body)
      expect(result['status']).to eq('queued')
      expect(result['count']).to eq(1)

      # Process the job
      perform_enqueued_jobs

      # Verify session created
      session = VisitorSession.find_by(session_id: session_id)
      expect(session).to be_present
      expect(session.business_id).to eq(business.id)
      expect(session.entry_page).to eq('/services')

      # Verify page view created
      page_view = PageView.find_by(session_id: session_id)
      expect(page_view).to be_present
      expect(page_view.is_entry_page).to be true

      # Step 2: Track click event
      click_event = {
        events: [{
          type: 'click',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: {
            element_type: 'button',
            element_text: 'Book Now',
            category: 'booking',
            action: 'click',
            page_path: '/services'
          }
        }]
      }

      expect {
        post api_v1_analytics_track_path, params: click_event
      }.to have_enqueued_job(AnalyticsIngestionJob)

      perform_enqueued_jobs

      # Verify click event created
      click = ClickEvent.find_by(session_id: session_id)
      expect(click).to be_present
      expect(click.element_text).to eq('Book Now')
      expect(click.category).to eq('booking')

      # Step 3: Track conversion
      conversion_event = {
        events: [{
          type: 'conversion',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: {
            conversion_type: 'booking_completed',
            conversion_value: 100.00,
            page_path: '/bookings/confirmation'
          }
        }]
      }

      expect {
        post api_v1_analytics_track_path, params: conversion_event
      }.to have_enqueued_job(AnalyticsIngestionJob)

      perform_enqueued_jobs

      # Verify conversion tracked
      session.reload
      expect(session.converted).to be true
      expect(session.conversion_type).to eq('booking_completed')
      expect(session.conversion_value).to eq(100.00)
    end
  end

  describe 'Privacy Compliance' do
    it 'respects Do Not Track header' do
      page_view_event = {
        events: [{
          type: 'page_view',
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: { page_path: '/' }
        }]
      }

      expect {
        post api_v1_analytics_track_path,
             params: page_view_event,
             headers: { 'DNT' => '1' }
      }.not_to have_enqueued_job(AnalyticsIngestionJob)

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result['status']).to eq('skipped')
      expect(result['reason']).to eq('privacy')
    end

    it 'blocks bot user agents' do
      page_view_event = {
        events: [{
          type: 'page_view',
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: { page_path: '/' }
        }]
      }

      expect {
        post api_v1_analytics_track_path,
             params: page_view_event,
             headers: { 'User-Agent' => 'Googlebot/2.1' }
      }.not_to have_enqueued_job(AnalyticsIngestionJob)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'Rate Limiting' do
    it 'enforces rate limit of 100 requests per minute per IP' do
      page_view_event = {
        events: [{
          type: 'page_view',
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: { page_path: '/' }
        }]
      }

      # Make 100 successful requests
      100.times do
        post api_v1_analytics_track_path, params: page_view_event
        expect(response).to have_http_status(:accepted)
      end

      # 101st request should be rate limited
      post api_v1_analytics_track_path, params: page_view_event
      expect(response).to have_http_status(:too_many_requests)

      result = JSON.parse(response.body)
      expect(result['error']).to eq('Rate limit exceeded')
    end
  end

  describe 'Input Validation' do
    it 'rejects non-array events parameter' do
      post api_v1_analytics_track_path, params: { events: 'not an array' }

      expect(response).to have_http_status(:bad_request)
      result = JSON.parse(response.body)
      expect(result['error']).to eq('Events must be an array')
    end

    it 'sanitizes input data' do
      malicious_event = {
        events: [{
          type: 'page_view',
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: {
            page_path: '/services',
            page_title: '<script>alert("xss")</script>' * 100, # Very long
            evil_field: 'should be filtered'
          }
        }]
      }

      post api_v1_analytics_track_path, params: malicious_event
      expect(response).to have_http_status(:accepted)

      perform_enqueued_jobs

      page_view = PageView.find_by(session_id: session_id)
      expect(page_view.page_title.length).to be <= 255
      expect(page_view.attributes.keys).not_to include('evil_field')
    end
  end

  describe 'Multi-tenant Isolation' do
    let(:other_business) { create(:business) }

    it 'isolates analytics data by business' do
      event = {
        events: [{
          type: 'page_view',
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          business_id: business.id,
          data: { page_path: '/services' }
        }]
      }

      post api_v1_analytics_track_path, params: event
      perform_enqueued_jobs

      # Data should only exist for the correct business
      expect(business.page_views.count).to eq(1)
      expect(other_business.page_views.count).to eq(0)

      expect(business.visitor_sessions.count).to eq(1)
      expect(other_business.visitor_sessions.count).to eq(0)
    end
  end
end
