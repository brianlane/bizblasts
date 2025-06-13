#!/usr/bin/env ruby

require_relative 'config/environment'

# Set up test data
business = Business.first || Business.create!(
  name: 'Test Business',
  hostname: 'testbiz',
  tier: 'free',
  host_type: 'subdomain'
)

ActsAsTenant.current_tenant = business

# Create a test product
product = business.products.first || business.products.create!(
  name: 'Test Product',
  description: 'A test product for promotion testing',
  price: 100.0,
  active: true
)

# Create a test service
service = business.services.first || business.services.create!(
  name: 'Test Service',
  description: 'A test service for promotion testing',
  duration: 60,
  price: 150.0,
  active: true
)

# Create a promotion for the product
promotion = business.promotions.find_by(code: 'SUMMER2024') || business.promotions.create!(
  name: 'Summer Sale',
  code: 'SUMMER2024',
  description: '20% off selected products',
  discount_type: 'percentage',
  discount_value: 20.0,
  start_date: 1.week.ago,
  end_date: 1.week.from_now,
  active: true,
  applicable_to_products: true,
  applicable_to_services: false
)

# Associate the promotion with the product (if not already associated)
unless promotion.promotion_products.exists?(product: product)
  promotion.promotion_products.create!(product: product)
end

puts "=== Promotional Pricing Test ==="
puts "Business: #{business.name}"
puts "Product: #{product.name} - Original Price: $#{product.price}"
puts "Service: #{service.name} - Original Price: $#{service.price}"
puts "Promotion: #{promotion.name} (#{promotion.discount_value}% off)"
puts ""

puts "=== Product Promotional Pricing ==="
puts "Product on promotion? #{product.on_promotion?}"
if product.on_promotion?
  puts "Promotional price: $#{product.promotional_price}"
  puts "Discount amount: $#{product.promotion_discount_amount}"
  puts "Savings percentage: #{product.savings_percentage}%"
  puts "Promotion display text: #{product.promotion_display_text}"
else
  puts "No active promotion for product"
end

puts ""
puts "=== Service Promotional Pricing ==="
puts "Service on promotion? #{service.on_promotion?}"
if service.on_promotion?
  puts "Promotional price: $#{service.promotional_price}"
  puts "Discount amount: $#{service.promotion_discount_amount}"
  puts "Savings percentage: #{service.savings_percentage}%"
  puts "Promotion display text: #{service.promotion_display_text}"
else
  puts "No active promotion for service"
end

puts ""
puts "=== Test Complete ===" 