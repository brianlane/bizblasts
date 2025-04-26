# frozen_string_literal: true

module SubdomainHelper
  def with_subdomain(subdomain)
    # Save original host
    original_host = Capybara.app_host
    # Set subdomain
    Capybara.app_host = subdomain ? "http://#{subdomain}.lvh.me:#{Capybara.server_port}" : "http://lvh.me:#{Capybara.server_port}"
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