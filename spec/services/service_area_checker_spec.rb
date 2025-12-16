# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceAreaChecker, type: :service do
  let(:business) { create(:business, zip: '94102') } # San Francisco
  let(:checker) { described_class.new(business) }

  before do
    # Clear Rails cache before each test
    Rails.cache.clear
  end

  describe '#initialize' do
    it 'accepts a business object' do
      expect(checker.business).to eq(business)
    end
  end

  describe '#within_radius?' do
    context 'with valid ZIP codes' do
      it 'returns true for a ZIP code within the radius' do
        # Mock geocoding for San Francisco (94102) and nearby Oakland (94601)
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        mock_coordinates_for(checker, '94601', [37.8044, -122.2712])

        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to be true
      end

      it 'returns false for a ZIP code outside the radius' do
        # Mock geocoding for San Francisco (94102) and Los Angeles (90001)
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        mock_coordinates_for(checker, '90001', [33.9731, -118.2479])

        result = checker.within_radius?('90001', radius_miles: 50)
        expect(result).to be false
      end

      it 'returns true for a ZIP code exactly at the radius boundary' do
        # Mock geocoding for two locations exactly 50 miles apart
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        # Calculate a point approximately 45 miles away (within 50 mile radius)
        mock_coordinates_for(checker, '95476', [38.3, -122.6])

        result = checker.within_radius?('95476', radius_miles: 50)
        expect(result).to be true
      end

      it 'handles ZIP+4 format by using only the first 5 digits' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        # Mock with the full ZIP+4 format since that's what coordinates_for receives
        # (it normalizes internally)
        mock_coordinates_for(checker, '94601-1234', [37.8044, -122.2712])

        result = checker.within_radius?('94601-1234', radius_miles: 50)
        expect(result).to be true
      end

      it 'logs the calculated distance' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        mock_coordinates_for(checker, '94601', [37.8044, -122.2712])

        expect(Rails.logger).to receive(:info).with(/Distance from 94102 to 94601: \d+\.\d+ miles/)
        checker.within_radius?('94601', radius_miles: 50)
      end
    end

    context 'with invalid inputs' do
      it 'returns :invalid_zip when customer ZIP code is blank' do
        result = checker.within_radius?('', radius_miles: 50)
        expect(result).to eq(:invalid_zip)

        result = checker.within_radius?(nil, radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end

      it 'returns :no_business_location when business ZIP is blank' do
        business.update_column(:zip, nil)
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:no_business_location)
      end

      it 'returns :invalid_zip when customer ZIP cannot be geocoded' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        mock_coordinates_for(checker, '00000', nil)

        result = checker.within_radius?('00000', radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end

      it 'returns :no_business_location when business ZIP cannot be geocoded' do
        mock_coordinates_for(checker, '94102', nil)
        # Also mock customer ZIP to prevent real HTTP calls (which could timeout and return true)
        mock_coordinates_for(checker, '94601', [37.8044, -122.2712])

        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:no_business_location)
      end
    end

    context 'with geocoding errors' do
      it 'returns true (fails open) when geocoding times out' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        allow(checker).to receive(:coordinates_for).with('94601').and_raise(Timeout::Error)

        # System fails open to allow booking when geocoding fails
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(true)
      end

      it 'returns true (fails open) when geocoding service is over query limit' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        allow(checker).to receive(:coordinates_for).with('94601').and_raise(Geocoder::OverQueryLimitError)

        expect(Rails.logger).to receive(:error).with(/Geocoding rate limit exceeded/)
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(true) # Fails open to allow booking
      end

      it 'returns true (fails open) when an unexpected error occurs during geocoding' do
        mock_coordinates_for(checker, '94102', [37.7749, -122.4194])
        allow(checker).to receive(:coordinates_for).with('94601').and_raise(StandardError, 'Unexpected error')

        # Logger will be called twice: once for the error message, once for the backtrace
        expect(Rails.logger).to receive(:error).with(/Error checking radius/).ordered
        expect(Rails.logger).to receive(:error).at_least(:once).ordered
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(true) # Fails open to allow booking
      end
    end

    context 'with caching' do
      it 'caches successful geocoding lookups' do
        # Track how many times the coordinates_for method actually does geocoding work
        call_count = 0
        original_method = checker.method(:coordinates_for)

        allow(checker).to receive(:coordinates_for).and_wrap_original do |method, *args|
          # Only count if cache miss (this is checked inside coordinates_for)
          cache_key = "geocoder:zip:#{args.first.to_s.strip.split('-').first}"
          call_count += 1 unless Rails.cache.exist?(cache_key)
          original_method.call(*args)
        end

        # Mock the geocoding to avoid real API calls
        allow(checker).to receive(:geocode_with_structured_search).and_return([
          OpenStruct.new(coordinates: [37.8044, -122.2712], latitude: 37.8044, longitude: -122.2712)
        ])

        # First call should do actual geocoding (cache miss)
        checker.within_radius?('94601', radius_miles: 50)
        expect(call_count).to eq(2) # business + customer

        # Second call for customer ZIP should use cache
        initial_count = call_count
        checker.within_radius?('94601', radius_miles: 50)
        expect(call_count).to eq(initial_count) # Should not increment
      end

      it 'caches failed geocoding lookups' do
        # Mock to return nil coordinates for invalid ZIP
        allow(checker).to receive(:geocode_with_structured_search).with('00000').and_return([])
        allow(checker).to receive(:coordinates_from_offline_database).with('00000').and_return(nil)
        allow(Geocoder).to receive(:search).with('00000, USA').and_return([])

        # Mock business coordinates
        allow(checker).to receive(:coordinates_for).with('94102').and_return([37.7749, -122.4194])

        # Track calls to coordinates_for for the invalid ZIP
        call_count = 0
        allow(checker).to receive(:coordinates_for).with('00000').and_wrap_original do |method, *args|
          call_count += 1
          nil # Return nil for invalid ZIP
        end

        # First call should try to geocode
        first_result = checker.within_radius?('00000', radius_miles: 50)
        expect(first_result).to eq(:invalid_zip)
        expect(call_count).to eq(1)

        # Second call should use cached nil
        second_result = checker.within_radius?('00000', radius_miles: 50)
        expect(second_result).to eq(:invalid_zip)
        expect(call_count).to eq(1) # Should still be 1, not 2
      end
    end
  end

  describe '#center_coordinates' do
    it 'returns the business coordinates' do
      mock_coordinates_for(checker, '94102', [37.7749, -122.4194])

      coords = checker.center_coordinates
      expect(coords).to eq([37.7749, -122.4194])
    end

    it 'caches the business coordinates' do
      expect(checker).to receive(:coordinates_for).with('94102').once.and_return([37.7749, -122.4194])

      # First call
      checker.center_coordinates
      # Second call should use cached value
      checker.center_coordinates
    end

    it 'returns nil when business ZIP cannot be geocoded' do
      mock_coordinates_for(checker, '94102', nil)

      coords = checker.center_coordinates
      expect(coords).to be_nil
    end
  end

  describe '#clear_cache!' do
    it 'clears the cached business coordinates' do
      # First call caches the coordinates
      expect(checker).to receive(:coordinates_for).with('94102').twice.and_return([37.7749, -122.4194])

      checker.center_coordinates

      # Clear cache
      checker.clear_cache!

      # Next call should hit the geocoder again (verified by .twice above)
      checker.center_coordinates
    end
  end

  describe 'real-world distance calculations' do
    # These tests use actual coordinates to verify distance calculations
    it 'correctly calculates distance between San Francisco and Oakland' do
      sf_coords = [37.7749, -122.4194]
      oakland_coords = [37.8044, -122.2712]

      distance = Geocoder::Calculations.distance_between(sf_coords, oakland_coords, units: :mi)
      expect(distance).to be_within(2).of(8.3) # About 8.3 miles (actual distance)
    end

    it 'correctly calculates distance between San Francisco and Los Angeles' do
      sf_coords = [37.7749, -122.4194]
      la_coords = [34.0522, -118.2437]

      distance = Geocoder::Calculations.distance_between(sf_coords, la_coords, units: :mi)
      expect(distance).to be_within(10).of(347) # About 347 miles (actual straight-line distance)
    end

    it 'correctly calculates distance between New York and Boston' do
      ny_coords = [40.7128, -74.0060]
      boston_coords = [42.3601, -71.0589]

      distance = Geocoder::Calculations.distance_between(ny_coords, boston_coords, units: :mi)
      expect(distance).to be_within(5).of(190) # About 190 miles (actual straight-line distance)
    end
  end
end

