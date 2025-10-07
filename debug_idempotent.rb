# Debug idempotent test issue

business = FactoryBot.create(:business, tier: 'premium', sms_enabled: true)
user = FactoryBot.create(:user, :client, email: 'user@example.com', phone: '6026866672')

# Create duplicate customers like in the test
customer_8_format = FactoryBot.create(:tenant_customer,
  business: business,
  email: 'customer8@example.com',
  phone: '6026866672',
  phone_opt_in: false,
  user_id: nil,
  created_at: 3.days.ago
)

customer_18_format = FactoryBot.create(:tenant_customer,
  business: business,
  email: 'customer18@example.com',
  phone: '+16026866672',
  phone_opt_in: true,
  phone_opt_in_at: 1.day.ago,
  user_id: nil,
  created_at: 1.day.ago
)

linker = CustomerLinker.new(business)

puts "=== First call ==="
puts "User phone: #{user.phone}"
puts "User phone_opt_in: #{user.phone_opt_in?}" if user.respond_to?(:phone_opt_in?)

first_result = linker.link_user_to_customer(user)
puts "First result: #{first_result.id}"
puts "First result phone: #{first_result.phone}"
puts "First result phone_opt_in: #{first_result.phone_opt_in?}"

puts "\n=== Second call ==="
puts "User phone: #{user.phone}"
puts "User phone_opt_in: #{user.phone_opt_in?}" if user.respond_to?(:phone_opt_in?)

second_result = linker.link_user_to_customer(user)
puts "Second result: #{second_result.id}"
puts "Second result phone: #{second_result.phone}"
puts "Second result phone_opt_in: #{second_result.phone_opt_in?}"

puts "\n=== Comparison ==="
puts "Same customer? #{first_result.id == second_result.id}"
puts "Phone formats: user='#{user.phone}', customer='#{second_result.phone}'"
puts "Phone different? #{user.phone != second_result.phone}"