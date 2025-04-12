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

RSpec.configure do |config|
  # Configure the driver to use for system tests
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  # Use cuprite for JS tests
  config.before(:each, type: :system, js: true) do
    driven_by :cuprite
  end
end 