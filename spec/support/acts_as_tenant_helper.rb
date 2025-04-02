# frozen_string_literal: true

# Helper for setting current tenant in tests
module ActsAsTenantHelper
  def with_tenant(tenant)
    old_tenant = ActsAsTenant.current_tenant
    ActsAsTenant.current_tenant = tenant
    yield
  ensure
    ActsAsTenant.current_tenant = old_tenant
  end
end

RSpec.configure do |config|
  config.include ActsAsTenantHelper

  # Reset ActsAsTenant.current_tenant after each test
  config.after(:each) do
    ActsAsTenant.current_tenant = nil
  end
end 