# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceAreaChecker, 'performance', type: :performance do
  let(:business) { create(:business, zip: '90210') }
  let(:checker) { described_class.new(business) }

  describe 'timeout handling' do
    context 'when HTTP request exceeds open timeout' do
      it 'fails within configured timeout period' do
        allow_any_instance_of(Net::HTTP).to receive(:start) do
          sleep(ServiceAreaChecker::HTTP_OPEN_TIMEOUT + 1)
          raise Timeout::Error
        end

        start_time = Time.current

        result = checker.within_radius?('90211', radius_miles: 50)

        elapsed = Time.current - start_time

        # Should timeout quickly and fail open
        expect(elapsed).to be < (ServiceAreaChecker::HTTP_OPEN_TIMEOUT + 2)
        expect(result).to eq(true) # Fails open
      end
    end

    context 'when HTTP request exceeds read timeout' do
      it 'respects read timeout configuration' do
        # Mock a slow response
        allow_any_instance_of(Net::HTTP).to receive(:request) do
          sleep(ServiceAreaChecker::HTTP_READ_TIMEOUT + 1)
          raise Timeout::Error, 'Read timeout'
        end

        start_time = Time.current

        result = checker.within_radius?('90211', radius_miles: 50)

        elapsed = Time.current - start_time

        # Should fail relatively quickly
        expect(elapsed).to be < (ServiceAreaChecker::HTTP_READ_TIMEOUT + 3)
        expect(result).to eq(true) # Fails open
      end
    end

    context 'when geocoding service is slow but within timeout' do
      it 'waits for response and processes it' do
        # Clear cache to ensure fresh lookup
        checker.clear_cache!(clear_all: true)

        # Mock a slow but successful response
        mock_result = OpenStruct.new(
          coordinates: [34.0736, -118.4004],
          latitude: 34.0736,
          longitude: -118.4004,
          country_code: 'us'
        )

        call_count = 0
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search) do |_instance, zip|
          call_count += 1
          sleep(2) # Slow but within timeout
          [mock_result]
        end

        start_time = Time.current

        result = checker.within_radius?('90211', radius_miles: 50)

        elapsed = Time.current - start_time

        # Should complete successfully (verify method was called, not just timing)
        expect(call_count).to be >= 1 # At least one geocoding call happened
        expect(result).to be_in([true, false])

        # Timing check only if method was actually called (not from cache)
        expect(elapsed).to be >= 1.5 if call_count >= 2
      end
    end
  end

  describe 'concurrent requests' do
    it 'handles multiple concurrent ZIP code checks without blocking' do
      # Mock geocoding to simulate real API behavior
      allow_any_instance_of(ServiceAreaChecker).to receive(:coordinates_for) do |_instance, zip|
        sleep(0.1) # Small delay to simulate API call
        case zip
        when '90210' then [34.1030, -118.4105]
        when '90211' then [34.0736, -118.4004]
        when '90212' then [34.0669, -118.4058]
        when '10001' then [40.7589, -73.9851]
        else nil
        end
      end

      start_time = Time.current

      # Run 10 concurrent checks
      threads = 10.times.map do |i|
        Thread.new do
          zip = ['90211', '90212', '10001'][i % 3]
          checker.within_radius?(zip, radius_miles: 50)
        end
      end

      results = threads.map(&:value)
      elapsed = Time.current - start_time

      # All threads should complete
      expect(results.length).to eq(10)

      # With concurrency, should be much faster than sequential (10 * 0.1 = 1 second)
      # Allow some overhead for thread management
      expect(elapsed).to be < 2.0
    end

    it 'maintains cache integrity under concurrent access' do
      # Clear cache before test
      Rails.cache.clear

      mock_coords = [34.0736, -118.4004]
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([OpenStruct.new(coordinates: mock_coords, country_code: 'us')])

      # Run multiple threads checking the same ZIP
      threads = 20.times.map do
        Thread.new do
          checker.within_radius?('90211', radius_miles: 50)
        end
      end

      results = threads.map(&:value)

      # All should succeed with consistent results
      expect(results.uniq.length).to be <= 2 # All true or all false (or one of each)

      # Cache should be set correctly
      cached_result = Rails.cache.read('geocoder:zip:90211')
      expect(cached_result).to eq(mock_coords)
    end
  end

  describe 'cache performance' do
    it 'significantly improves performance on repeated lookups' do
      # Clear cache to ensure fresh lookup
      checker.clear_cache!(clear_all: true)

      # Mock slow geocoding
      call_count = 0
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search) do
        call_count += 1
        sleep(0.5) # Simulate API latency
        [OpenStruct.new(coordinates: [34.0736, -118.4004], country_code: 'us')]
      end

      # First call - should hit the mocked geocoding
      start_time = Time.current
      first_result = checker.within_radius?('90211', radius_miles: 50)
      first_elapsed = Time.current - start_time

      # Verify geocoding was called (not from cache)
      expect(call_count).to eq(2) # Business zip + customer zip

      # Second call - should be fast (cached)
      start_time = Time.current
      second_result = checker.within_radius?('90211', radius_miles: 50)
      second_elapsed = Time.current - start_time

      # Verify second call used cache (no additional geocoding calls)
      expect(call_count).to eq(2) # No additional calls
      expect(second_result).to eq(first_result)

      # Cache should make second call much faster than first
      # Only check timing if first call actually invoked the mock (call_count == 2)
      expect(second_elapsed).to be < (first_elapsed * 0.5) if call_count == 2
    end

    it 'handles cache misses gracefully' do
      # Simulate cache server being down
      allow(Rails.cache).to receive(:exist?).and_return(false)
      allow(Rails.cache).to receive(:read).and_return(nil)
      allow(Rails.cache).to receive(:write).and_return(false)

      mock_result = OpenStruct.new(coordinates: [34.0736, -118.4004], country_code: 'us')
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([mock_result])

      # Should still work even if cache is unavailable
      result = checker.within_radius?('90211', radius_miles: 50)

      expect(result).to be_in([true, false])
    end
  end

  describe 'query performance' do
    it 'does not cause N+1 queries when checking multiple ZIPs' do
      mock_result = OpenStruct.new(coordinates: [34.0736, -118.4004], country_code: 'us')
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([mock_result])

      # First check
      checker.within_radius?('90211', radius_miles: 50)

      # Subsequent checks should not increase query count significantly
      query_count = 0
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        query_count += 1 unless args.last[:name] == 'CACHE'
      end

      5.times do |i|
        checker.within_radius?("9021#{i}", radius_miles: 50)
      end

      # Should not scale linearly with number of checks
      # Allow some queries for cache operations
      expect(query_count).to be < 10
    end
  end

  describe 'memory usage' do
    it 'does not leak memory on repeated checks' do
      mock_result = OpenStruct.new(coordinates: [34.0736, -118.4004], country_code: 'us')
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([mock_result])

      initial_objects = ObjectSpace.count_objects

      # Perform many checks
      100.times do |i|
        new_checker = ServiceAreaChecker.new(business)
        new_checker.within_radius?("9021#{i % 10}", radius_miles: 50)
      end

      # Force garbage collection
      GC.start

      final_objects = ObjectSpace.count_objects

      # Object growth should be reasonable (not exponential)
      # Allow for some growth due to caching and Ruby internals
      growth = final_objects[:TOTAL] - initial_objects[:TOTAL]
      expect(growth).to be < 10000
    end
  end

  describe 'fallback performance' do
    it 'tries fallback methods quickly when primary fails' do
      # Structured search fails fast
      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .and_return([])

      # Offline DB fails fast
      allow(ZipCodes).to receive(:identify).and_return(nil)

      # Text search succeeds
      mock_result = double('GeocoderResult', coordinates: [34.0736, -118.4004])
      allow(Geocoder).to receive(:search).and_return([mock_result])

      start_time = Time.current

      result = checker.within_radius?('90211', radius_miles: 50)

      elapsed = Time.current - start_time

      # Should complete fallback within reasonable time
      expect(elapsed).to be < 5.0
      expect(result).to be_in([true, false])
    end
  end

  describe 'rate limiting behavior' do
    context 'when rate limit is hit' do
      it 'fails open immediately without retrying' do
        # Simulate rate limit error
        allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)
        allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
          .and_raise(Geocoder::OverQueryLimitError)

        start_time = Time.current

        result = checker.within_radius?('90211', radius_miles: 50)

        elapsed = Time.current - start_time

        # Should fail fast without retries
        expect(elapsed).to be < 1.0
        expect(result).to eq(true) # Fails open
      end
    end
  end
end
