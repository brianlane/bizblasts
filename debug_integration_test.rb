#!/usr/bin/env ruby

# Minimal test to debug the 500 error
require 'rails_helper'

puts '=== Testing Integration Test 500 Error ==='

# Use the same setup as the integration test
custom_domain_business = FactoryBot.create(:business, :with_custom_domain,
  hostname: 'debug-test.com', tier: 'premium', status: 'cname_active')
custom_domain_user = FactoryBot.create(:user,
  business: custom_domain_business, role: 'manager', password: 'password123')

puts "Business: #{custom_domain_business.hostname}"
puts "User: #{custom_domain_user.email}"

# Setup the application for testing
app = Rails.application

# Create a test request
env = Rack::MockRequest.env_for('/auth/bridge', {
  method: 'GET',
  'HTTP_HOST' => 'www.debug-test.com',
  params: {
    target_url: "https://debug-test.com/dashboard",
    business_id: custom_domain_business.id
  }
})

# Setup Warden for the request (this might be missing)
warden = Warden::Proxy.new(env, Warden::Manager.new(Rails.application))
env['warden'] = warden

# Sign in the user through Warden
warden.set_user(custom_domain_user, scope: :user)

puts "Request setup complete, making request..."

begin
  status, headers, response = app.call(env)
  puts "Status: #{status}"
  puts "Headers: #{headers}"
  if status == 500
    puts "Response body: #{response.body if response.respond_to?(:body)}"
    if response.is_a?(Array)
      puts "Response: #{response.join}"
    end
  end
rescue => e
  puts "Exception: #{e.class}: #{e.message}"
  puts e.backtrace.first(10)
end