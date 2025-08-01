require 'capybara/rspec'
require 'capybara/cuprite'

# Configure Capybara for system tests
Capybara.register_driver(:cuprite) do |app|
  options = {
    window_size: [1200, 800],
    # Browser options for CI/Docker compatibility
    # Minimal browser options - only essential for CI stability
    browser_options: { 
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil
    },
    headless: ENV['HEADLESS'] != 'false',
    inspector: ENV['INSPECTOR'] == 'true',
    js_errors: true,
    dialog_handler: ->(page, dialog) { dialog.accept }
  }

  # CI-specific settings for better stability
  if ENV['CI'] == 'true'
    options.merge!({
      process_timeout: 30,     # Increased timeout for CI
      timeout: 30,             # Increased timeout for CI
      slowmo: 0.1,             # Add slight delay between commands
      browser_options: options[:browser_options].merge({
        'single-process' => nil,
        'no-zygote' => nil,
        'memory-pressure-off' => nil,
        'max_old_space_size' => '2048'
      })
    })
  else
    options.merge!({
      process_timeout: 15,
      timeout: 15
    })
  end

  Capybara::Cuprite::Driver.new(app, **options)
end

# Use cuprite for JS tests
Capybara.javascript_driver = :cuprite

# Configure test timeouts
if ENV['CI'] == 'true'
  Capybara.default_max_wait_time = 15 # seconds - reduced for CI speed
  Capybara.server_errors = []        # Don't raise server errors in CI
else
  Capybara.default_max_wait_time = 30 # seconds
end

# Configure the default host for Capybara tests
Capybara.server_host = 'lvh.me'
# Don't override server_port here - let rails_helper.rb set it for parallel tests
# Capybara.server_port = 3001 # Use a specific port
Capybara.app_host = "http://#{Capybara.server_host}:#{Capybara.server_port}"
Capybara.default_host = Capybara.app_host

RSpec.configure do |config|
  # Configure the driver to use for system tests
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  # Use cuprite for JS tests
  config.before(:each, type: :system, js: true) do
    driven_by :cuprite
    # Set app_host here too, potentially overriding based on test context if needed
    # Ensure host includes port
    Capybara.app_host = "http://#{Capybara.server_host}:#{Capybara.server_port}"
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

  # Configure RSpec to use Capybara DSL in system tests
  # These might already be included via rails_helper requiring support files
  # config.include Capybara::DSL, type: :system
  # config.include Capybara::RSpecMatchers, type: :system

  # Include custom system helpers (Assuming this is done in rails_helper)
  # config.include SystemHelpers, type: :system
end 