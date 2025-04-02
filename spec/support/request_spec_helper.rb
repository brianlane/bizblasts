# frozen_string_literal: true

# Helper module for request specs
module RequestSpecHelper
  include Warden::Test::Helpers

  def self.included(base)
    base.before { Warden.test_mode! }
    base.after { Warden.test_reset! }
  end

  # Sign in helper for request specs
  def sign_in(user)
    login_as(user, scope: :user)
  end

  # Sign out helper for request specs
  def sign_out
    logout(:user)
  end
  
  # Helper to change tenant in tests
  def with_tenant(tenant)
    old_tenant = ActsAsTenant.current_tenant
    ActsAsTenant.current_tenant = tenant
    yield
  ensure
    ActsAsTenant.current_tenant = old_tenant
  end
end 