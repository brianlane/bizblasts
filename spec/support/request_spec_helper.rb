# frozen_string_literal: true

# Helper module for request specs
module RequestSpecHelper
  include Warden::Test::Helpers

  def self.included(base)
    base.before { Warden.test_mode! }
    base.after { Warden.test_reset! }
  end

  # Sign in helper for request specs
  def sign_in(user, options = {})
    scope = options[:scope] || (user.is_a?(AdminUser) ? :admin_user : :user)
    
    if scope == :admin_user
      # For ActiveAdmin, we need special handling
      login_as(user, scope: scope)
      
      # Before we perform the request, set the current admin user
      # This is necessary because ActiveAdmin uses a different authentication method
      allow_any_instance_of(ActionDispatch::Request)
        .to receive(:env)
        .and_wrap_original do |original, *args|
          env = original.call(*args)
          
          # Create a more complete warden double
          warden = double('warden')
          allow(warden).to receive(:authenticate!).and_return(user)
          allow(warden).to receive(:authenticate).and_return(user)
          allow(warden).to receive(:user).with(:admin_user).and_return(user)
          allow(warden).to receive(:user).with(:user).and_return(nil)
          allow(warden).to receive(:user).with(no_args).and_return(user)
          
          # Add manager method that returns a manager mock
          manager = double('manager')
          allow(manager).to receive(:session_serializer).and_return(double('serializer', store: user, fetch: user))
          allow(warden).to receive(:manager).and_return(manager)
          
          env['warden'] = warden
          env
        end
    else
      login_as(user, scope: scope)
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