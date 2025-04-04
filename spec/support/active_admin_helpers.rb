# frozen_string_literal: true

# Helper module for ActiveAdmin testing
module ActiveAdminHelpers
  # Sign in as an admin user using FactoryBot
  def sign_in_admin
    # Use FactoryBot sequence to ensure uniqueness in parallel tests
    @admin_user ||= create(:admin_user)
    sign_in @admin_user
  end
  
  # Return the admin auth headers for requests using FactoryBot
  def admin_headers
    admin = @admin_user || create(:admin_user) # Reuse if already created in the same example
    
    # For controller specs
    { 'HTTP_AUTHORIZATION' => "Basic #{Base64.encode64("#{admin.email}:#{admin.password}")}" }
  end
end