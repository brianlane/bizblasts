#!/usr/bin/env ruby

puts '=== Testing Authentication Bridge Integration Issue ==='

# Recreate the exact scenario from the failing test
begin
  # Find or create the business type as the test
  custom_domain_business = Business.find_by(hostname: 'example.com') ||
    FactoryBot.create(:business, :with_custom_domain,
      hostname: 'example.com',
      tier: 'premium',
      status: 'cname_active'
    )

  custom_domain_user = User.where(business: custom_domain_business, role: 'manager').first ||
    FactoryBot.create(:user,
      business: custom_domain_business,
      role: 'manager',
      password: 'password123'
    )

  puts "Created business: #{custom_domain_business.hostname} (ID: #{custom_domain_business.id})"
  puts "Created user: #{custom_domain_user.email} (ID: #{custom_domain_user.id})"
  puts "Business canonical_domain: #{custom_domain_business.canonical_domain.inspect}"
  puts "Business custom_domain_allow?: #{custom_domain_business.custom_domain_allow?}"

  # Test the controller validation methods
  controller = AuthenticationBridgeController.new

  # Mock request similar to the test
  mock_request = ActionDispatch::TestRequest.create({
    'HTTP_HOST' => 'www.example.com',
    'REQUEST_METHOD' => 'GET',
    'HTTP_USER_AGENT' => 'Mozilla/5.0 (Test)'
  })

  controller.request = mock_request

  puts "\n=== Testing Controller Validations ==="
  puts "main_domain_request?: #{controller.send(:main_domain_request?)}"
  puts "valid_bridge_request?: #{controller.send(:valid_bridge_request?)}"

  target_url = "https://example.com/dashboard"
  puts "valid_target_url?: #{controller.send(:valid_target_url?, target_url, custom_domain_business.id)}"

rescue => e
  puts "Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end