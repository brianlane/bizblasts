# Debug the data integrity issue

business = FactoryBot.create(:business, tier: 'premium', sms_enabled: true)
user = FactoryBot.create(:user, :client, email: 'user@example.com', phone: '6026866672')

# Create the duplicate customers
customer_8_format = FactoryBot.create(:tenant_customer,
  business: business,
  email: 'customer8@example.com',
  phone: '6026866672',
  phone_opt_in: false,
  user_id: nil,
  created_at: 3.days.ago
)

customer_9_format = FactoryBot.create(:tenant_customer,
  business: business,
  email: 'customer9@example.com',
  phone: '16026866672',
  phone_opt_in: false,
  user_id: nil,
  created_at: 2.days.ago
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

# Link customer_18 to other user
other_user = FactoryBot.create(:user, :client, email: 'other@example.com', phone: '5551234567')
customer_18_format.update!(user_id: other_user.id)

puts "=== Before link_user_to_customer ==="
puts "Customers:"
business.tenant_customers.each do |c|
  puts "  Customer #{c.id}: phone=#{c.phone}, user_id=#{c.user_id}"
end

linker = CustomerLinker.new(business)

# Test what resolve_phone_duplicates returns
puts "\n=== Testing resolve_phone_duplicates ==="
canonical = linker.resolve_phone_duplicates(user.phone)
if canonical
  puts "Canonical customer: #{canonical.id} (user_id: #{canonical.user_id})"
else
  puts "No canonical customer found"
end

# Test what find_customers_by_phone returns
puts "\n=== Testing find_customers_by_phone ==="
phone_customers = linker.send(:find_customers_by_phone, user.phone)
puts "Found #{phone_customers.count} customers with phone #{user.phone}:"
phone_customers.each do |c|
  puts "  Customer #{c.id}: phone=#{c.phone}, user_id=#{c.user_id}"
end

# Now test the link_user_to_customer
puts "\n=== Testing link_user_to_customer ==="
result_customer = linker.link_user_to_customer(user)
puts "Result customer: #{result_customer.id} (user_id: #{result_customer.user_id})"

puts "\n=== After link_user_to_customer ==="
puts "Customers:"
business.tenant_customers.reload.each do |c|
  puts "  Customer #{c.id}: phone=#{c.phone}, user_id=#{c.user_id}"
end

# Check for data integrity issue
same_phone_customers = business.tenant_customers.where(
  'phone IN (?)',
  ['+16026866672', '16026866672', '6026866672']
).where.not(user_id: nil)

user_ids = same_phone_customers.pluck(:user_id).uniq
puts "\nData integrity check:"
puts "Users linked to same phone: #{user_ids}"
puts "Count: #{user_ids.count} (should be 1)"