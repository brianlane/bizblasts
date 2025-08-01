# Test script for calendar models
puts 'Testing calendar models...'

# Create a test business and staff member
business = Business.create!(
  name: 'Test Business',
  email: 'test@example.com',
  phone: '555-0123',
  address: '123 Test St',
  city: 'Test City',
  state: 'TS',
  zip: '12345',
  description: 'Test business',
  tier: 'standard',
  industry: 'consulting',
  host_type: 'subdomain',
  hostname: "testcal#{Time.current.to_i}"
)

user = User.create!(
  email: "staffcal#{Time.current.to_i}@example.com",
  password: 'password123',
  password_confirmation: 'password123',
  role: 'manager',
  business: business,
  first_name: 'Test',
  last_name: 'Staff'
)

staff_member = business.staff_members.create!(
  user: user,
  active: true
)

# Test calendar connection creation
ActsAsTenant.with_tenant(business) do
  connection = business.calendar_connections.create!(
    staff_member: staff_member,
    provider: 'google',
    uid: 'test-google-uid',
    access_token: 'test-access-token',
    refresh_token: 'test-refresh-token',
    token_expires_at: 1.hour.from_now,
    scopes: 'https://www.googleapis.com/auth/calendar',
    connected_at: Time.current,
    active: true
  )
  
  puts "Calendar connection created: #{connection.id}"
  puts "Provider: #{connection.provider}"
  puts "Active: #{connection.active?}"
  puts "Staff member: #{connection.staff_member.user.email}"
end

puts 'Calendar models test completed successfully!'