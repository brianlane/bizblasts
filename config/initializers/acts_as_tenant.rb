# config/initializers/acts_as_tenant.rb

# Configure ActsAsTenant to use Thread global storage
ActsAsTenant.configure do |config|
  config.require_tenant = false # We'll handle tenant availability
end 