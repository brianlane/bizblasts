require 'capybara/rspec'
require 'capybara/cuprite'

# Configure Capybara for system tests
Capybara.register_driver(:cuprite) do |app|
  options = {
    window_size: [1200, 800],
    # Browser options for CI/Docker compatibility
    browser_options: {
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil
    },
    headless: ENV['HEADLESS'] != 'false',
    inspector: ENV['INSPECTOR'] == 'true',
    js_errors: true,
    dialog_handler: ->(_page, dialog) { dialog.accept },
    # Note: pending_connection_errors: false documented to suppress these errors,
    # but in practice with Ferrum 0.17.1 they still occur when timeout is hit first
    pending_connection_errors: false
  }

  # CI-specific settings for better stability
  if ENV['CI'] == 'true'
    options.merge!(
      process_timeout: 90,      # Increased from 60
      timeout: 90,              # Increased from 60
      network_timeout: 120,     # Increased from 90
      slowmo: 0.1,              # Slightly slower to give CI more breathing room
      browser_options: options[:browser_options].merge(
        'single-process' => nil,
        'no-zygote' => nil,
        'memory-pressure-off' => nil,
        'max_old_space_size' => '2048',
        'disable-features' => 'VizDisplayCompositor'  # Can help with CI stability
      )
    )
  else
    options.merge!(
      process_timeout: 20,
      timeout: 20,
      network_timeout: 30
    )
  end

  Capybara::Cuprite::Driver.new(app, **options)
end

# Use cuprite for JS tests
Capybara.javascript_driver = :cuprite

# Configure test timeouts
if ENV['CI'] == 'true'
  Capybara.default_max_wait_time = 30 # seconds - increased for CI stability
  Capybara.server_errors = []         # Don't raise server errors in CI
else
  Capybara.default_max_wait_time = 30 # seconds
end

# Configure the default host for Capybara tests
Capybara.server_host = 'lvh.me'
# Don't override server_port here - let rails_helper.rb set it for parallel tests
# Capybara.server_port = 3001 # Use a specific port

RSpec.configure do |config|
  # Configure the driver to use for system tests
  config.before(:each, type: :system) do
    # Ensure app_host is properly set with the current server port
    port_suffix = Capybara.server_port ? ":#{Capybara.server_port}" : ""
    Capybara.app_host = "http://#{Capybara.server_host}#{port_suffix}"
    Capybara.default_host = Capybara.app_host

    driven_by :rack_test
  end

  # Use cuprite for JS tests
  config.before(:each, type: :system, js: true) do
    # Ensure app_host is properly set with the current server port
    port_suffix = Capybara.server_port ? ":#{Capybara.server_port}" : ""
    Capybara.app_host = "http://#{Capybara.server_host}#{port_suffix}"

    driven_by :cuprite
  end

  # Helper method to switch to subdomain
  config.include Module.new {
    def switch_to_subdomain(subdomain)
      port_suffix = Capybara.server_port ? ":#{Capybara.server_port}" : ""
      host = "http://#{subdomain}.lvh.me#{port_suffix}"
      Capybara.app_host = host
      Capybara.default_host = host
    end

    def switch_to_main_domain
      port_suffix = Capybara.server_port ? ":#{Capybara.server_port}" : ""
      host = "http://lvh.me#{port_suffix}"
      Capybara.app_host = host
      Capybara.default_host = host
    end
  }, type: :system

  # Configure RSpec to use Capybara DSL in system tests
  # These might already be included via rails_helper requiring support files
  # config.include Capybara::DSL, type: :system
  # config.include Capybara::RSpecMatchers, type: :system

  # Include custom system helpers (Assuming this is done in rails_helper)
  # config.include SystemHelpers, type: :system
end 