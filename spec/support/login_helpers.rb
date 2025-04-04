# frozen_string_literal: true

# Helpers for testing login functionality
module LoginHelpers
  # Sign in a user for testing
  def sign_in_user(user = nil)
    @user = user || create(:user)
    sign_in @user
    @user
  end

  # Create a test user
  def create_test_user(business = nil)
    business ||= create_tenant
    User.create!(
      email: "user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      business: business
    )
  end
end 