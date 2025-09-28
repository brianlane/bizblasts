#!/usr/bin/env ruby

puts 'Testing basic authentication bridge controller functionality...'

# Create a test business and user
business = Business.first || FactoryBot.create(:business, :with_custom_domain, hostname: 'example.com')
user = User.first || FactoryBot.create(:user, business: business, role: 'manager')

puts "Business: #{business.hostname} (ID: #{business.id})"
puts "User: #{user.email} (ID: #{user.id})"

# Check if routes are accessible
begin
  puts 'Testing AuthToken creation...'
  mock_request = OpenStruct.new(
    remote_ip: '127.0.0.1',
    user_agent: 'Test',
    headers: {}
  )
  token = AuthToken.create_for_user!(user, 'https://example.com/test', mock_request)
  puts "Token created successfully: #{token.token[0..8]}..."
rescue => e
  puts "Error creating token: #{e.class}: #{e.message}"
  puts e.backtrace.first(3)
end