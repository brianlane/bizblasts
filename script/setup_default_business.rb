#!/usr/bin/env ruby

# Rails runner script to set up Default Business for manual testing
# Usage: rails runner setup_default_business.rb

puts "Setting up Default Business for manual testing..."

# Find or create Default Business
business = Business.find_or_create_by(hostname: 'default-business') do |b|
  b.name = 'Default Business'
  b.industry = 'hair_salons'  # Using a valid industry from SHOWCASE_INDUSTRY_MAPPINGS
  b.phone = '555-123-4567'
  b.email = 'default@example.com'
  b.website = 'https://default-business.example.com'
  b.address = '123 Main St'
  b.city = 'Default City'
  b.state = 'CA'
  b.zip = '12345'
  b.description = 'Default business for testing cross-access prevention'
  b.host_type = 'subdomain'
  b.show_services_section = true
  b.show_products_section = true
  b.show_estimate_page = true
  b.status = 'active'
end

puts "✓ Default Business created/found: #{business.name} (ID: #{business.id})"

# Ensure business is saved and has an ID
business.save! if business.new_record?
puts "Business ID: #{business.id}"

# Set the tenant context for this business
ActsAsTenant.current_tenant = business

# Create staff members if they don't exist
staff_member1 = StaffMember.find_or_create_by(business_id: business.id, name: 'John Smith') do |s|
  s.business = business
  s.email = 'john.smith@default-business.com'
  s.phone = '555-111-1111'
  s.position = 'Senior Stylist'
end

staff_member2 = StaffMember.find_or_create_by(business_id: business.id, name: 'Jane Doe') do |s|
  s.business = business
  s.email = 'jane.doe@default-business.com'
  s.phone = '555-222-2222'
  s.position = 'Manager'
end

puts "✓ Staff members created:"
puts "  - #{staff_member1.name} (#{staff_member1.email})"
puts "  - #{staff_member2.name} (#{staff_member2.email})"

# Create availability for staff members using JSONB format
puts "Creating availability for staff members..."

availability_schedule = {
  "monday" => [
    { "start" => "09:00", "end" => "12:00" },
    { "start" => "13:00", "end" => "17:00" }
  ],
  "tuesday" => [
    { "start" => "09:00", "end" => "12:00" },
    { "start" => "13:00", "end" => "17:00" }
  ],
  "wednesday" => [
    { "start" => "09:00", "end" => "12:00" },
    { "start" => "13:00", "end" => "17:00" }
  ],
  "thursday" => [
    { "start" => "09:00", "end" => "12:00" },
    { "start" => "13:00", "end" => "17:00" }
  ],
  "friday" => [
    { "start" => "09:00", "end" => "12:00" },
    { "start" => "13:00", "end" => "17:00" }
  ],
  "saturday" => [
    { "start" => "10:00", "end" => "16:00" }
  ],
  "sunday" => []
}

[staff_member1, staff_member2].each do |staff|
  staff.update!(availability: availability_schedule)
end

puts "✓ Availability created for all staff members (Mon-Fri: 9 AM - 12 PM, 1 PM - 5 PM; Sat: 10 AM - 4 PM)"

# Create services
service1 = Service.find_or_create_by(business: business, name: 'Haircut') do |s|
  s.description = 'Professional haircut service'
  s.duration = 60
  s.price = 45.00
  s.active = true
end

service2 = Service.find_or_create_by(business: business, name: 'Hair Styling') do |s|
  s.description = 'Professional hair styling service'
  s.duration = 90
  s.price = 75.00
  s.active = true
end

service3 = Service.find_or_create_by(business: business, name: 'Hair Color') do |s|
  s.description = 'Professional hair coloring service'
  s.duration = 120
  s.price = 120.00
  s.active = true
end

# Assign services to staff members
[service1, service2, service3].each do |service|
  [staff_member1, staff_member2].each do |staff|
    ServicesStaffMember.find_or_create_by(service: service, staff_member: staff)
  end
end

puts "✓ Services created:"
puts "  - #{service1.name} ($#{service1.price}, #{service1.duration} min)"
puts "  - #{service2.name} ($#{service2.price}, #{service2.duration} min)"
puts "  - #{service3.name} ($#{service3.price}, #{service3.duration} min)"

# Create products
product1 = Product.find_or_create_by(business: business, name: 'Premium Shampoo') do |p|
  p.description = 'High-quality shampoo for all hair types'
  p.price = 25.00
  p.product_type = 'standard'
  p.active = true
  p.stock_quantity = 50
end

product2 = Product.find_or_create_by(business: business, name: 'Hair Conditioner') do |p|
  p.description = 'Moisturizing conditioner for smooth hair'
  p.price = 22.00
  p.product_type = 'standard'
  p.active = true
  p.stock_quantity = 45
end

product3 = Product.find_or_create_by(business: business, name: 'Hair Styling Gel') do |p|
  p.description = 'Strong hold styling gel'
  p.price = 18.00
  p.product_type = 'standard'
  p.active = true
  p.stock_quantity = 30
end

product4 = Product.find_or_create_by(business: business, name: 'Hair Care Kit') do |p|
  p.description = 'Complete hair care set with shampoo, conditioner, and styling products'
  p.price = 65.00
  p.product_type = 'mixed'
  p.active = true
  p.stock_quantity = 20
end

# Create product variants for the mixed product
if product4.product_type == 'mixed'
  variant1 = ProductVariant.find_or_create_by(product: product4, name: 'Basic Kit') do |v|
    v.price_modifier = 0.00
    v.stock_quantity = 15
    v.sku = "kit-basic-#{product4.id}"
  end
  
  variant2 = ProductVariant.find_or_create_by(product: product4, name: 'Deluxe Kit') do |v|
    v.price_modifier = 15.00
    v.stock_quantity = 10
    v.sku = "kit-deluxe-#{product4.id}"
  end
  
  variant3 = ProductVariant.find_or_create_by(product: product4, name: 'Professional Kit') do |v|
    v.price_modifier = 25.00
    v.stock_quantity = 8
    v.sku = "kit-professional-#{product4.id}"
  end
end

puts "✓ Products created:"
puts "  - #{product1.name} ($#{product1.price})"
puts "  - #{product2.name} ($#{product2.price})"
puts "  - #{product3.name} ($#{product3.price})"
puts "  - #{product4.name} ($#{product4.price}) with variants"

# Create a shipping method
shipping_method = ShippingMethod.find_or_create_by(business: business, name: 'Standard Shipping') do |sm|
  sm.cost = 8.99
  sm.active = true
end

puts "✓ Shipping method created: #{shipping_method.name} ($#{shipping_method.cost})"

# Create a tax rate
tax_rate = TaxRate.find_or_create_by(business: business, name: 'CA Sales Tax') do |tr|
  tr.rate = 0.0825  # 8.25% as decimal
  tr.region = 'California'
  tr.applies_to_shipping = false
end

puts "✓ Tax rate created: #{tax_rate.name} (#{(tax_rate.rate * 100).round(2)}%)"

# Create test users for different businesses to test cross-access prevention
puts "\nCreating test users for cross-business access testing..."

# Create another business to test cross-access
other_business = Business.find_or_create_by(hostname: 'other-business') do |b|
  b.name = 'Other Business'
  b.industry = 'boutiques'  # Using a valid industry from SHOWCASE_INDUSTRY_MAPPINGS
  b.phone = '555-999-8888'
  b.email = 'other@example.com'
  b.website = 'https://other-business.example.com'
  b.address = '456 Other St'
  b.city = 'Other City'
  b.state = 'NY'
  b.zip = '54321'
  b.description = 'Another business for testing cross-access prevention'
  b.host_type = 'subdomain'
  b.show_services_section = true
  b.show_products_section = true
  b.status = 'active'
end

# Create manager for Default Business
manager_default = User.find_or_create_by(email: 'manager@default-business.com') do |u|
  u.first_name = 'Default'
  u.last_name = 'Manager'
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'manager'
  u.business = business
  u.confirmed_at = Time.current
end

# Create staff for Default Business  
staff_default = User.find_or_create_by(email: 'staff@default-business.com') do |u|
  u.first_name = 'Default'
  u.last_name = 'Staff'
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'staff'
  u.business = business
  u.confirmed_at = Time.current
end

# Create manager for Other Business
manager_other = User.find_or_create_by(email: 'manager@other-business.com') do |u|
  u.first_name = 'Other'
  u.last_name = 'Manager'
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'manager'
  u.business = other_business
  u.confirmed_at = Time.current
end

# Create a client user
client_user = User.find_or_create_by(email: 'client@example.com') do |u|
  u.first_name = 'Test'
  u.last_name = 'Client'
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'client'
  u.confirmed_at = Time.current
end

puts "✓ Test users created:"
puts "  - Default Manager: manager@default-business.com (password: password123)"
puts "  - Default Staff: staff@default-business.com (password: password123)"
puts "  - Other Manager: manager@other-business.com (password: password123)"
puts "  - Test Client: client@example.com (password: password123)"

puts "\n" + "="*60
puts "SETUP COMPLETE!"
puts "="*60
puts "\nDefault Business Setup Summary:"
puts "Business: #{business.name} (#{business.hostname}.lvh.me:3000)"
puts "Services: #{Service.where(business: business).count} services available"
puts "Products: #{Product.where(business: business).count} products available"
puts "Staff: #{StaffMember.where(business: business).count} staff members with availability"
puts "\nOther Business for Testing:"
puts "Business: #{other_business.name} (#{other_business.hostname}.lvh.me:3000)"
puts "\nTest Users:"
puts "- manager@default-business.com / password123 (Default Business Manager)"
puts "- staff@default-business.com / password123 (Default Business Staff)"
puts "- manager@other-business.com / password123 (Other Business Manager)"
puts "- client@example.com / password123 (Client - can access any business)"

puts "\n" + "="*60
puts "MANUAL TESTING INSTRUCTIONS:"
puts "="*60
puts "1. Start your Rails server: rails server"
puts "2. Test access on different subdomains:"
puts "   - Default Business: http://default-business.lvh.me:3000"
puts "   - Other Business: http://other-business.lvh.me:3000"
puts ""
puts "3. Test Cross-Business Access Prevention:"
puts "   a) Sign in as manager@default-business.com on default-business.lvh.me:3000"
puts "   b) Try to access: http://other-business.lvh.me:3000/products"
puts "   c) Should see: 'You must sign out and proceed as a guest'"
puts ""
puts "4. Test Allowed Access:"
puts "   a) Sign in as client@example.com on any subdomain"
puts "   b) Should be able to access products/booking on any business"
puts ""
puts "5. Test Booking with Service:"
puts "   - Visit: http://default-business.lvh.me:3000/book?service_id=#{service1.id}"
puts "   - Available services: Haircut, Hair Styling, Hair Color"
puts ""
puts "6. Test Shopping Cart:"
puts "   - Visit: http://default-business.lvh.me:3000/products"
puts "   - Add products to cart and test cart access"

puts "\nSetup completed successfully! 🎉" 