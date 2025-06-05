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