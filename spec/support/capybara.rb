require 'capybara/rspec'
require 'selenium-webdriver'

# Configure Capybara for system tests
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--window-size=1400,1400')
  
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Use headless Chrome for JS tests, and rack_test for non-JS tests
Capybara.javascript_driver = :headless_chrome

# Configure test timeouts
Capybara.default_max_wait_time = 10 # seconds

RSpec.configure do |config|
  # Configure the driver to use for system tests
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :headless_chrome
  end
end 