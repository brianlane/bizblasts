# frozen_string_literal: true

# Helper module for ActiveAdmin testing
module ActiveAdminHelpers
  # Sign in as an admin user
  def sign_in_admin
    @admin_user ||= AdminUser.first || AdminUser.create!(
      email: 'admin@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
    
    sign_in @admin_user
  end
  
  # Return the admin auth headers for requests
  def admin_headers
    admin = AdminUser.first || AdminUser.create!(
      email: 'admin@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
    
    # For controller specs
    { 'HTTP_AUTHORIZATION' => "Basic #{Base64.encode64("#{admin.email}:password123")}" }
  end
end 