# frozen_string_literal: true

# Global Geocoder stubbing for tests to prevent real HTTP requests
# This significantly improves test performance by avoiding 5-second timeouts
# on every Business creation with address components.

RSpec.configure do |config|
  # Stub Geocoder globally before each test
  config.before(:each) do
    # Stub Geocoder.search to return a mock result with timezone info
    allow(Geocoder).to receive(:search).and_return([
      double(
        coordinates: [37.7749, -122.4194], # San Francisco coordinates as default
        latitude: 37.7749,
        longitude: -122.4194,
        country_code: 'us',
        timezone: 'America/Los_Angeles',
        data: {
          'timezone' => 'America/Los_Angeles'
        }
      )
    ])
  end

  # For tests that need specific Geocoder behavior, they can override this stub
  # Example in spec file:
  #   allow(Geocoder).to receive(:search).with("specific address").and_return([...])
end
