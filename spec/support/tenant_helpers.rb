# frozen_string_literal: true

# Helpers for testing multi-tenant functionality
module TenantHelpers
  # Set the current tenant for the test
  def set_tenant(business)
    ActsAsTenant.current_tenant = business
  end

  # Reset the tenant after the test
  def reset_tenant
    ActsAsTenant.current_tenant = nil
  end

  # Create a test business tenant
  def create_tenant
    Business.create!(
      name: "Test Business #{SecureRandom.hex(4)}",
      subdomain: "test#{Time.now.to_i}#{rand(100)}"
    )
  end
end 