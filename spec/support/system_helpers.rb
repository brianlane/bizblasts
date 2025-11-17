# frozen_string_literal: true

# Helper module for system tests with subdomain support
module SystemHelpers
  # Sign in a user with optional subdomain support
  def sign_in_as(user, options = {})
    # Set subdomain if specified
    if options[:subdomain]
      Capybara.app_host = "http://#{options[:subdomain]}.example.com"
    else
      Capybara.app_host = "http://www.example.com"
    end

    # Use login_as from Warden::Test::Helpers for simplicity
    login_as(user, scope: :user)

    # Visit the specified path or fallback to root
    visit(options[:path] || root_path)

    # Return the user for chaining
    user
  end

  # Wait for page to be truly idle (all network requests complete)
  # This is especially important in CI environments where network latency
  # can cause pending connections that trigger Ferrum::PendingConnectionsError
  #
  # Works in both CI and local environments for consistent behavior
  def wait_for_page_load(timeout: 5)
    return unless page.driver.respond_to?(:browser)

    if ENV['CI'] == 'true'
      # In CI: Use Ferrum's network idle detection
      begin
        page.driver.browser.network.wait_for_idle(timeout: timeout)
      rescue Ferrum::TimeoutError
        # Log but don't fail - page might be loaded enough to continue
        Rails.logger.debug "[System Test] Network not idle after #{timeout}s, continuing anyway"
      rescue NoMethodError
        # network.wait_for_idle may not be available in all Ferrum versions
        Rails.logger.debug "[System Test] Network idle wait not available, skipping"
      end
    else
      # In local development: Use Capybara's default wait mechanism
      # This ensures consistent behavior without the overhead of network monitoring
      begin
        # Wait for document.readyState to be complete
        page.evaluate_script('document.readyState')
        # Brief pause to allow any pending AJAX requests to start
        sleep 0.5
      rescue StandardError => e
        Rails.logger.debug "[System Test] Page load wait skipped: #{e.message}"
      end
    end
  end

  # Visit a path and wait for network to be idle
  # Use this for pages with heavy JavaScript or external resources
  # This method provides consistent behavior in both CI and local environments
  def visit_and_wait(path, wait_time: 5)
    visit(path)
    wait_for_page_load(timeout: wait_time)
  end

  # Dismiss cookie consent banner if present
  # This is a common pattern across many tests and should be standardized
  def dismiss_cookie_banner_if_present
    return unless page.has_css?('#termly-code-snippet-support', wait: 2)

    begin
      within('#termly-code-snippet-support', wait: 2) do
        click_button 'Accept'
      end
      # Brief pause for JavaScript to process the acceptance
      sleep 0.2
    rescue Capybara::ElementNotFound
      # Banner may have disappeared during wait, that's fine
      Rails.logger.debug "[System Test] Cookie banner not found or already dismissed"
    end
  end

  # Helper method to select from custom dropdowns
  # Usage: select_from_custom_dropdown("Option Text", "dropdown_type")
  # Supports: "Tax Rate", "Shipping Method", "Customer", "User Role", "User", "Integration Type"
  def select_from_custom_dropdown(option_text, dropdown_type)
    case dropdown_type.downcase
    when 'tax rate', 'tax_rate'
      # Click the tax dropdown button
      find('[data-tax-dropdown-target="button"]', wait: 5).click
      # Click the option
      find('[data-tax-dropdown-target="option"]', text: option_text, wait: 5).click
    when 'shipping', 'shipping method', 'shipping_method'
      # Click the shipping dropdown button
      find('[data-shipping-dropdown-target="button"]', wait: 5).click
      # Click the option
      find('[data-shipping-dropdown-target="option"]', text: option_text, wait: 5).click
    when 'customer'
      # Click the customer dropdown button
      find('[data-customer-dropdown-target="button"]', wait: 5).click
      # Wait for menu to become visible
      expect(page).to have_selector('[data-customer-dropdown-target="menu"]:not(.hidden)', wait: 5)
      # Parse the option text to get customer name and email
      if option_text.include?('(') && option_text.include?(')')
        # Extract customer name (everything before the opening parenthesis)
        customer_name = option_text.split(' (').first.strip
        # Find the option that contains the customer name
        find('[data-customer-dropdown-target="option"]', text: customer_name, wait: 5).click
      else
        # For exact text matches (like "Create new customer")
        find('[data-customer-dropdown-target="option"]', text: option_text, wait: 5).click
      end
    when 'user role', 'role'
      # Click the role dropdown button
      find('[data-role-dropdown-target="button"]', wait: 5).click
      # Click the option
      find('[data-role-dropdown-target="option"]', text: option_text, wait: 5).click
    when 'user'
      # Click the user dropdown button
      find('[data-user-dropdown-target="button"]', wait: 5).click
      # Click the option
      find('[data-user-dropdown-target="option"]', text: option_text, wait: 5).click
    when 'integration type', 'integration'
      # Click the integration dropdown button
      find('[data-integration-dropdown-target="button"]', wait: 5).click
      # Click the option
      find('[data-integration-dropdown-target="option"]', text: option_text, wait: 5).click
    else
      # Fallback to standard select for other dropdowns
      select option_text, from: dropdown_type
    end
  end
end

# Include these helpers in system tests
RSpec.configure do |config|
  config.include SystemHelpers, type: :system
  config.include SystemHelpers, type: :feature
end 