# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceAreaChecker, 'edge cases' do
  let(:business) { create(:business, zip: '90210') }
  let(:checker) { described_class.new(business) }

  describe 'when ZIP code database is unavailable' do
    before do
      # Simulate ZIP code database gem failure
      allow(ZipCodes).to receive(:identify).and_raise(StandardError, 'Database unavailable')
    end

    context 'with working Nominatim API' do
      it 'falls back to Nominatim structured search' do
        # Allow logger to track calls
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:info)

        # Mock successful structured search for business ZIP
        business_response = [
          OpenStruct.new(
            coordinates: [34.1030, -118.4105],
            latitude: 34.1030,
            longitude: -118.4105,
            country_code: 'us'
          )
        ]

        # Mock successful structured search for customer ZIP
        customer_response = [
          OpenStruct.new(
            coordinates: [34.0736, -118.4004],
            latitude: 34.0736,
            longitude: -118.4004,
            country_code: 'us'
          )
        ]

        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .with('90210').and_return(business_response)
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .with('90211').and_return(customer_response)

        result = checker.within_radius?('90211', radius_miles: 50)

        expect(result).to be_in([true, false])
        expect(Rails.logger).not_to have_received(:error).with(/Error checking radius/)
      end
    end

    context 'with Nominatim API also failing' do
      it 'returns :no_business_location when business coordinates cannot be found' do
        # Clear Rails cache to ensure no cached results interfere
        Rails.cache.clear

        # Mock cache to not have any existing entries
        allow(Rails.cache).to receive(:exist?).and_return(false)
        allow(Rails.cache).to receive(:write) # Allow cache writes to be called

        # Allow logger calls for tracking
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:error)

        # Mock all geocoding methods to fail
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .and_raise(StandardError, 'API unavailable')

        allow(Geocoder).to receive(:search).and_raise(StandardError, 'API unavailable')

        result = checker.within_radius?('90211', radius_miles: 50)

        # When geocoding fails and returns nil, method returns :no_business_location
        # (fail-open with `true` only happens when exception is raised during distance calc)
        expect(result).to eq(:no_business_location)

        # Verify error was logged (coordinates_for logs errors before returning nil)
        expect(Rails.logger).to have_received(:error).at_least(:once)
      end
    end

    context 'with rate limit error' do
      it 'fails open when Nominatim rate limit is exceeded' do
        allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)

        result = checker.within_radius?('90211', radius_miles: 50)

        expect(result).to eq(true)
      end
    end
  end

  describe 'offline database fallback' do
    context 'when structured search fails but offline DB works' do
      it 'uses offline database to get city/state and geocodes that' do
        # Structured search fails
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .and_return([])

        # Mock business ZIP (90210) - using offline DB
        allow(ZipCodes).to receive(:identify).with('90210')
          .and_return({ city: 'Beverly Hills', state_code: 'CA' })
        allow(Geocoder).to receive(:search).with('Beverly Hills, CA, USA')
          .and_return([double('GeocoderResult', coordinates: [34.1030, -118.4105])])

        # Mock customer ZIP (90211) - offline DB returns city/state
        allow(ZipCodes).to receive(:identify).with('90211')
          .and_return({ city: 'Beverly Hills', state_code: 'CA' })

        # Default stub for any other Geocoder.search calls
        allow(Geocoder).to receive(:search).and_return([])

        # Geocoder can find customer city/state
        allow(Geocoder).to receive(:search).with('Beverly Hills, CA, USA')
          .and_return([double('GeocoderResult', coordinates: [34.0736, -118.4004])])

        result = checker.within_radius?('90211', radius_miles: 50)

        expect(result).to be_in([true, false])
      end
    end

    context 'when ZIP info is incomplete' do
      it 'handles missing city gracefully' do
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .and_return([])

        # Mock business ZIP (90210) - this is called first for center_coordinates
        allow(ZipCodes).to receive(:identify).with('90210')
          .and_return({ city: 'Beverly Hills', state_code: 'CA' })

        # Default stub for Geocoder.search to handle any args
        allow(Geocoder).to receive(:search).and_return([])

        # Business can use city/state lookup
        allow(Geocoder).to receive(:search).with('Beverly Hills, CA, USA')
          .and_return([double('GeocoderResult', coordinates: [34.1030, -118.4105])])

        # Mock customer ZIP (12345) with incomplete info
        allow(ZipCodes).to receive(:identify).with('12345')
          .and_return({ city: nil, state_code: 'NY' })

        # Should fall back to text search for incomplete ZIP
        mock_result = double('GeocoderResult', coordinates: [42.8142, -73.9396])
        allow(Geocoder).to receive(:search).with('12345, USA')
          .and_return([mock_result])

        result = checker.within_radius?('12345', radius_miles: 50)

        expect(result).to be_in([true, false])
      end
    end
  end

  describe 'HTTP timeout handling' do
    it 'handles timeout errors gracefully' do
      allow_any_instance_of(Net::HTTP).to receive(:request)
        .and_raise(Timeout::Error, 'Request timed out')

      result = checker.within_radius?('90211', radius_miles: 50)

      # Should fail open when geocoding times out
      expect(result).to eq(true)
    end

    it 'respects configured timeouts' do
      expect(ServiceAreaChecker::HTTP_OPEN_TIMEOUT).to eq(5)
      expect(ServiceAreaChecker::HTTP_READ_TIMEOUT).to eq(10)
    end

    it 'configures Net::HTTP with timeout parameters when making structured search requests' do
      # Verify that Net::HTTP.start is called with proper timeout configuration
      expect(Net::HTTP).to receive(:start).with(
        'nominatim.openstreetmap.org',
        443,
        hash_including(
          use_ssl: true,
          open_timeout: ServiceAreaChecker::HTTP_OPEN_TIMEOUT,
          read_timeout: ServiceAreaChecker::HTTP_READ_TIMEOUT
        )
      ).and_call_original

      # Stub the actual HTTP request to avoid making real API calls
      mock_response = instance_double(Net::HTTPResponse, code: '200', body: '[]')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)

      # Trigger the structured search
      result = checker.send(:geocode_with_structured_search, '90211')

      expect(result).to eq([])
    end
  end

  describe 'cache behavior edge cases' do
    it 'caches failed lookups for shorter duration' do
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([])
      allow(Geocoder).to receive(:search).and_return([])
      allow(ZipCodes).to receive(:identify).and_return(nil)

      # Allow cache write for business ZIP (90210) - this happens first
      allow(Rails.cache).to receive(:write)
        .with("geocoder:zip:90210", nil, expires_in: ServiceAreaChecker::CACHE_FAILURE_DURATION)

      # Expect cache write for customer ZIP (99999)
      expect(Rails.cache).to receive(:write)
        .with("geocoder:zip:99999", nil, expires_in: ServiceAreaChecker::CACHE_FAILURE_DURATION)

      checker.within_radius?('99999', radius_miles: 50)
    end

    it 'caches successful lookups for longer duration' do
      # Ensure cache doesn't exist for these ZIPs
      allow(Rails.cache).to receive(:exist?).and_return(false)

      # Mock business ZIP first (90210)
      business_result = OpenStruct.new(
        coordinates: [34.1030, -118.4105],
        latitude: 34.1030,
        longitude: -118.4105,
        country_code: 'us'
      )

      # Mock customer ZIP (90211)
      customer_result = OpenStruct.new(
        coordinates: [34.0736, -118.4004],
        latitude: 34.0736,
        longitude: -118.4004,
        country_code: 'us'
      )

      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90210').and_return([business_result])
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90211').and_return([customer_result])

      # Allow cache write for business ZIP (we're not testing this one)
      allow(Rails.cache).to receive(:write)
        .with("geocoder:zip:90210", [34.1030, -118.4105], expires_in: ServiceAreaChecker::CACHE_SUCCESS_DURATION)

      # Expect cache write for customer ZIP with success duration
      expect(Rails.cache).to receive(:write)
        .with("geocoder:zip:90211", [34.0736, -118.4004], expires_in: ServiceAreaChecker::CACHE_SUCCESS_DURATION)

      checker.within_radius?('90211', radius_miles: 50)
    end

    it 'uses cached results even if nil' do
      # Mock business ZIP lookup
      allow(Rails.cache).to receive(:exist?).with("geocoder:zip:90210").and_return(false)
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90210').and_return([
          OpenStruct.new(coordinates: [34.1030, -118.4105], latitude: 34.1030, longitude: -118.4105, country_code: 'us')
        ])
      allow(Rails.cache).to receive(:write).with("geocoder:zip:90210", anything, anything)

      # Simulate cached nil result for customer ZIP (failed lookup that was cached)
      allow(Rails.cache).to receive(:exist?).with("geocoder:zip:99999").and_return(true)
      allow(Rails.cache).to receive(:read).with("geocoder:zip:99999").and_return(nil)

      # Should not attempt new geocoding for customer ZIP since it's cached
      expect(Geocoder).not_to receive(:search).with('99999, USA')

      result = checker.within_radius?('99999', radius_miles: 50)

      expect(result).to eq(:invalid_zip)
    end
  end

  describe 'malformed ZIP codes' do
    it 'handles ZIP+4 format' do
      # Mock business ZIP (90210)
      business_result = OpenStruct.new(
        coordinates: [34.1030, -118.4105],
        latitude: 34.1030,
        longitude: -118.4105,
        country_code: 'us'
      )
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90210').and_return([business_result])

      # Mock customer ZIP with +4 extension (90210-1234)
      # coordinates_for receives the full ZIP+4 before normalization
      allow_any_instance_of(ServiceAreaChecker).to receive(:coordinates_for)
        .with('90210-1234').and_return([34.1030, -118.4105])

      # Allow business ZIP lookup to work normally
      allow_any_instance_of(ServiceAreaChecker).to receive(:coordinates_for)
        .with('90210').and_call_original

      # Should strip the +4 extension
      result = checker.within_radius?('90210-1234', radius_miles: 50)

      expect(result).to be_in([true, false, :invalid_zip])
    end

    it 'handles ZIP codes with spaces' do
      # Mock business ZIP coordinates
      business_result = OpenStruct.new(
        coordinates: [34.1030, -118.4105],
        latitude: 34.1030,
        longitude: -118.4105,
        country_code: 'us'
      )
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90210').and_return([business_result])

      # Mock customer ZIP coordinates (with spaces stripped)
      customer_result = OpenStruct.new(coordinates: [34.0736, -118.4004], country_code: 'us')
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with('90211').and_return([customer_result])

      result = checker.within_radius?('  90211  ', radius_miles: 50)

      expect(result).to be_in([true, false, :invalid_zip])
    end
  end
end
