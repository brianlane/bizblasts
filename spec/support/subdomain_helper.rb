# frozen_string_literal: true

module SubdomainHelper
  def with_subdomain(subdomain)
    # Save original host
    original_host = Capybara.app_host
    
    # Set subdomain using TenantHost helper for consistency
    if subdomain
      mock_business = double('Business', 
        subdomain: subdomain, 
        hostname: subdomain, 
        host_type_subdomain?: true, 
        host_type_custom_domain?: false
      )
      request = create_test_request(port: Capybara.server_port)
      Capybara.app_host = TenantHost.url_for(mock_business, request, '')
    else
      Capybara.app_host = "http://lvh.me:#{Capybara.server_port}"
    end
    
    yield
  ensure
    # Restore original host
    Capybara.app_host = original_host
  end
end

RSpec.configure do |config|
  config.include SubdomainHelper, type: :system
  config.include SubdomainHelper, type: :feature
end