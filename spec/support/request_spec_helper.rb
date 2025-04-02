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
    if user.is_a?(AdminUser)
      # For ActiveAdmin, we need special handling
      login_as(user, scope: :admin_user)
      
      # Before we perform the request, set the current admin user
      # This is necessary because ActiveAdmin uses a different authentication method
      allow_any_instance_of(ActionDispatch::Request)
        .to receive(:env)
        .and_wrap_original do |original, *args|
          env = original.call(*args)
          env['warden'] ||= double
          allow(env['warden']).to receive(:authenticate!).and_return(user)
          allow(env['warden']).to receive(:authenticate).and_return(user)
          allow(env['warden']).to receive(:user).with(:admin_user).and_return(user)
          allow(env['warden']).to receive(:user).with(:user).and_return(nil)
          allow(env['warden']).to receive(:user).with(no_args).and_return(user)
          env
        end
    else
      login_as(user, scope: :user)
    end
  end

  # Sign out helper for request specs
  def sign_out(scope = nil)
    if scope
      logout(scope)
    else
      logout
    end
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