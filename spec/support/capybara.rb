require 'capybara/rspec'
require 'capybara/cuprite'

# Configure Capybara for system tests
Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1400, 1400], headless: true)
end

# Use cuprite for JS tests
Capybara.javascript_driver = :cuprite

# Configure test timeouts
Capybara.default_max_wait_time = 10 # seconds

# Configure the default host for Capybara tests
Capybara.server_port = 9887
Capybara.app_host = "http://lvh.me:#{Capybara.server_port}"
Capybara.always_include_port = true
Capybara.default_host = "http://lvh.me"

RSpec.configure do |config|
  # Configure the driver to use for system tests
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  # Use cuprite for JS tests
  config.before(:each, type: :system, js: true) do
    driven_by :cuprite
  end
  
  # Helper method to switch to subdomain
  config.include Module.new {
    def switch_to_subdomain(subdomain)
      Capybara.app_host = "http://#{subdomain}.lvh.me:#{Capybara.server_port}"
    end

    def switch_to_main_domain
      Capybara.app_host = "http://lvh.me:#{Capybara.server_port}"
    end
  }, type: :system
end 