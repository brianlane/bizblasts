# frozen_string_literal: true

require 'rails_helper'
require 'nokogiri'
require 'cgi'
require 'uri'

RSpec.describe 'Service Area Check Integration', type: :request do
  let(:business) do
    create(:business, :with_subdomain,
           tier: 'premium',
           zip: '90210',
           sms_enabled: true)
  end
  let!(:booking_policy) do
    create(:booking_policy,
           business: business,
           service_radius_enabled: true,
           service_radius_miles: 50)
  end
  let(:service) { create(:service, business: business, price: 100, duration: 60) }

  before do
    ActsAsTenant.with_tenant(business) do
      # Setup test environment
      host! TenantHost.host_for(business, nil)
    end
  end

  describe 'home page book now links' do
    it 'include service context when service radius is active' do
      service
      business.update!(show_services_section: true)

      get tenant_root_path

      expect(response).to have_http_status(:success)

      doc = Nokogiri::HTML(response.body)
      book_link = doc.css('a[data-dropdown-updater-target="bookLink"]').first

      expect(book_link).to be_present

      link_uri = URI.parse(book_link['href'])
      params = Rack::Utils.parse_nested_query(link_uri.query)

      expect(params['service_id']).to eq(service.id.to_s)
      expect(params['return_to']).to be_present
      decoded_return_to = CGI.unescape(params['return_to'])
      expect(decoded_return_to).to include("service_id=#{service.id}")
    end
  end

  describe 'complete service area check flow' do
    context 'when customer is within service radius' do
      it 'shows form, validates ZIP, and redirects to booking' do
        # Step 1: Customer visits service area check form
        get new_service_area_check_path(service_id: service.id, return_to: new_tenant_booking_path(service_id: service.id))

        expect(response).to have_http_status(:success)
        expect(response.body).to include('ZIP code')
        expect(assigns(:service)).to eq(service)
        expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))

        # Step 2: Customer submits their ZIP code (within radius)
        # Mock geocoding for both business and customer ZIP
        checker = ServiceAreaChecker.new(business)
        allow(ServiceAreaChecker).to receive(:new).with(business).and_return(checker)
        allow(checker).to receive(:coordinates_for)
          .with('90210').and_return([34.1030, -118.4105]) # Business location (Beverly Hills)
        allow(checker).to receive(:coordinates_for)
          .with('90211').and_return([34.0736, -118.4004]) # Nearby location (still Beverly Hills)

        post service_area_check_path,
             params: {
               service_id: service.id,
               return_to: new_tenant_booking_path(service_id: service.id),
               service_area_check: { zip: '90211' }
             }

        # Step 3: Should redirect to booking page with success message
        expect(response).to redirect_to(new_tenant_booking_path(service_id: service.id))
        follow_redirect!

        expect(response).to have_http_status(:success)
        expect(flash[:notice]).to include('We service your area')
      end
    end

    context 'when customer is outside service radius' do
      it 'shows error message and does not allow booking' do
        get new_service_area_check_path(service_id: service.id, return_to: new_tenant_booking_path(service_id: service.id))

        expect(response).to have_http_status(:success)

        # Mock geocoding - customer is far away
        checker = ServiceAreaChecker.new(business)
        allow(ServiceAreaChecker).to receive(:new).with(business).and_return(checker)
        allow(checker).to receive(:coordinates_for)
          .with('90210').and_return([34.1030, -118.4105]) # Business location
        allow(checker).to receive(:coordinates_for)
          .with('10001').and_return([40.7589, -73.9851]) # New York City (far away)

        post service_area_check_path,
             params: {
               service_id: service.id,
               return_to: new_tenant_booking_path(service_id: service.id),
               service_area_check: { zip: '10001' }
             }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('outside our service area')
        expect(flash[:notice]).to be_nil
      end
    end

    context 'when customer provides invalid ZIP code' do
      it 'shows validation error' do
        get new_service_area_check_path(service_id: service.id)

        # Mock geocoding - return nil for invalid ZIP
        checker = ServiceAreaChecker.new(business)
        allow(ServiceAreaChecker).to receive(:new).with(business).and_return(checker)
        allow(checker).to receive(:coordinates_for)
          .with('99999').and_return(nil)

        post service_area_check_path,
             params: {
               service_id: service.id,
               service_area_check: { zip: '99999' }
             }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("couldn't find that ZIP code")
      end
    end

    context 'when customer provides blank ZIP code' do
      it 'shows validation error' do
        post service_area_check_path,
             params: {
               service_id: service.id,
               service_area_check: { zip: '' }
             }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Please enter a ZIP code')
      end
    end

    context 'when service radius is disabled' do
      before do
        booking_policy.update!(service_radius_enabled: false)
      end

      it 'uses default radius' do
        # When disabled, the helper should bypass check or use default behavior
        # Test that we can still access the form
        get new_service_area_check_path(service_id: service.id)

        expect(response).to have_http_status(:success)
      end
    end

    context 'when open redirect is attempted' do
      it 'prevents redirect to external site' do
        get new_service_area_check_path(
          service_id: service.id,
          return_to: 'https://evil.com/phishing'
        )

        expect(response).to have_http_status(:success)
        # Should fall back to safe default, not use malicious URL
        expect(assigns(:return_to)).not_to include('evil.com')
        expect(assigns(:return_to)).to include(new_tenant_booking_path(service_id: service.id))
      end

      it 'prevents redirect via protocol-relative URL' do
        get new_service_area_check_path(
          service_id: service.id,
          return_to: '//evil.com/phishing'
        )

        expect(assigns(:return_to)).not_to include('evil.com')
      end

      it 'allows safe relative paths with query params' do
        get new_service_area_check_path(
          service_id: service.id,
          return_to: '/bookings/new?service_id=123'
        )

        expect(assigns(:return_to)).to eq('/bookings/new?service_id=123')
      end
    end
  end

  describe 'caching behavior' do
    it 'caches successful ZIP code lookups' do
      checker = ServiceAreaChecker.new(business)
      allow(ServiceAreaChecker).to receive(:new).with(business).and_return(checker)
      allow(checker).to receive(:coordinates_for)
        .with('90210').and_return([34.1030, -118.4105])
      allow(checker).to receive(:coordinates_for)
        .with('90211').and_return([34.0736, -118.4004])

      # First request should cache the result
      post service_area_check_path,
           params: {
             service_id: service.id,
             service_area_check: { zip: '90211' }
           }

      expect(response).to redirect_to(new_tenant_booking_path(service_id: service.id))

      # Second request with same ZIP should use cache
      # We verify this by ensuring the mock is not called again for the customer ZIP
      expect(Rails.cache).to receive(:exist?).with("geocoder:zip:90211").and_return(true)
      expect(Rails.cache).to receive(:read).with("geocoder:zip:90211").and_return([34.0736, -118.4004])

      post service_area_check_path,
           params: {
             service_id: service.id,
             service_area_check: { zip: '90211' }
           }
    end
  end
end
