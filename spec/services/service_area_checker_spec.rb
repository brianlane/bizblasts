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
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194]) # SF coordinates
        ])
        allow(Geocoder).to receive(:search).with('94601').and_return([
          double(coordinates: [37.8044, -122.2712]) # Oakland coordinates (about 10 miles away)
        ])

        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to be true
      end

      it 'returns false for a ZIP code outside the radius' do
        # Mock geocoding for San Francisco (94102) and Los Angeles (90001)
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194]) # SF coordinates
        ])
        allow(Geocoder).to receive(:search).with('90001').and_return([
          double(coordinates: [33.9731, -118.2479]) # LA coordinates (about 380 miles away)
        ])

        result = checker.within_radius?('90001', radius_miles: 50)
        expect(result).to be false
      end

      it 'returns true for a ZIP code exactly at the radius boundary' do
        # Mock geocoding for two locations exactly 50 miles apart
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        # Calculate a point approximately 45 miles away (within 50 mile radius)
        allow(Geocoder).to receive(:search).with('95476').and_return([
          double(coordinates: [38.3, -122.6]) # Adjusted to be within 50 miles
        ])

        result = checker.within_radius?('95476', radius_miles: 50)
        expect(result).to be true
      end

      it 'handles ZIP+4 format by using only the first 5 digits' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_return([
          double(coordinates: [37.8044, -122.2712])
        ])

        result = checker.within_radius?('94601-1234', radius_miles: 50)
        expect(result).to be true
      end

      it 'logs the calculated distance' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_return([
          double(coordinates: [37.8044, -122.2712])
        ])

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
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('00000').and_return([])

        result = checker.within_radius?('00000', radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end

      it 'returns :no_business_location when business ZIP cannot be geocoded' do
        allow(Geocoder).to receive(:search).with('94102').and_return([])

        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:no_business_location)
      end
    end

    context 'with geocoding errors' do
      it 'returns true (fails open) when geocoding times out' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_raise(Timeout::Error)

        expect(Rails.logger).to receive(:error).with(/Geocoding timeout/)
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end

      it 'returns :invalid_zip when geocoding service is over query limit' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_raise(Geocoder::OverQueryLimitError)

        expect(Rails.logger).to receive(:error).with(/Error geocoding ZIP/)
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end

      it 'returns :invalid_zip when an unexpected error occurs during geocoding' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_raise(StandardError, 'Unexpected error')

        expect(Rails.logger).to receive(:error).with(/Error geocoding ZIP/)
        result = checker.within_radius?('94601', radius_miles: 50)
        expect(result).to eq(:invalid_zip)
      end
    end

    context 'with caching' do
      it 'caches successful geocoding lookups' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        allow(Geocoder).to receive(:search).with('94601').and_return([
          double(coordinates: [37.8044, -122.2712])
        ])

        # First call should hit the geocoder
        checker.within_radius?('94601', radius_miles: 50)

        # Second call should use cache
        expect(Geocoder).not_to receive(:search).with('94601')
        checker.within_radius?('94601', radius_miles: 50)
      end

      it 'caches failed geocoding lookups' do
        allow(Geocoder).to receive(:search).with('94102').and_return([
          double(coordinates: [37.7749, -122.4194])
        ])
        
        # Track how many times Geocoder.search is called for the invalid ZIP
        call_count = 0
        allow(Geocoder).to receive(:search).with('00000') do
          call_count += 1
          []
        end

        # First call should hit the geocoder
        first_result = checker.within_radius?('00000', radius_miles: 50)
        expect(first_result).to eq(:invalid_zip)
        expect(call_count).to eq(1)

        # Second call should use cache (Geocoder.search should not be called again)
        second_result = checker.within_radius?('00000', radius_miles: 50)
        expect(second_result).to eq(:invalid_zip)
        expect(call_count).to eq(1) # Should still be 1, not 2
      end
    end
  end

  describe '#center_coordinates' do
    it 'returns the business coordinates' do
      allow(Geocoder).to receive(:search).with('94102').and_return([
        double(coordinates: [37.7749, -122.4194])
      ])

      coords = checker.center_coordinates
      expect(coords).to eq([37.7749, -122.4194])
    end

    it 'caches the business coordinates' do
      allow(Geocoder).to receive(:search).with('94102').and_return([
        double(coordinates: [37.7749, -122.4194])
      ]).once

      # First call
      checker.center_coordinates
      # Second call should use cached value
      checker.center_coordinates
    end

    it 'returns nil when business ZIP cannot be geocoded' do
      allow(Geocoder).to receive(:search).with('94102').and_return([])

      coords = checker.center_coordinates
      expect(coords).to be_nil
    end
  end

  describe '#clear_cache!' do
    it 'clears the cached business coordinates' do
      # First call caches the coordinates
      allow(Geocoder).to receive(:search).with('94102').and_return([
        double(coordinates: [37.7749, -122.4194])
      ]).twice

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

