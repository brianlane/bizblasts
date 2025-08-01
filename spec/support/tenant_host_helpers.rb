# frozen_string_literal: true

# Spec helper for generating tenant host URLs in tests
# Provides consistent helpers for test scenarios
module TenantHostHelpers
  # Generate a host for a business in test scenarios
  def host_for(business, request = nil)
    request ||= ActionDispatch::TestRequest.create
    TenantHost.host_for(business, request)
  end

  # Generate a full URL for a business in test scenarios
  def url_for_business(business, path = '/', request = nil)
    request ||= ActionDispatch::TestRequest.create
    TenantHost.url_for(business, request, path)
  end

  # Helper for creating test request objects with specific domains/ports
  def create_test_request(domain: 'lvh.me', port: 3000, protocol: 'http://')
    request = ActionDispatch::TestRequest.create
    request.host = domain
    request.port = port
    allow(request).to receive(:protocol).and_return(protocol)
    allow(request).to receive(:domain).and_return(domain)
    request
  end
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include TenantHostHelpers
end