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
end

# Include these helpers in system tests
RSpec.configure do |config|
  config.include SystemHelpers, type: :system
  config.include SystemHelpers, type: :feature
end 