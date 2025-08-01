# Prevent loading this file multiple times in the same process (e.g., during parallel tests)
return if defined?(SEEDS_LOADED)

# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# This file creates sample data for development.
# The code is idempotent so it can be run multiple times without creating duplicates.
# Only require faker in development or test
if Rails.env.development? || Rails.env.test?
  require 'faker'
end

# Check if we're running in minimal seed mode (for faster tests)
MINIMAL_SEED = ENV['MINIMAL_SEED'] == '1'

# Helper method to calculate a weekday date (Monday-Friday)
def calculate_weekday_date(date)
  # Convert to the beginning of day to avoid time issues
  date = date.beginning_of_day
  # If it's a weekend, move to Monday
  if date.saturday?
    date += 2.days
  elsif date.sunday?
    date += 1.day
  end
  date
end

puts "Seeding database with sample data..."

puts "--- DEBUG: Rails environment: #{Rails.env}"
puts "--- DEBUG: Rails version: #{Rails.version}"
puts "--- DEBUG: ActiveRecord version: #{ActiveRecord::VERSION::STRING}"
puts "--- DEBUG: Business.industries: #{Business.industries.inspect}"
puts "--- DEBUG: Business.tiers: #{Business.tiers.inspect}"
puts "--- DEBUG: Business.host_types: #{Business.host_types.inspect}"
puts "--- DEBUG: Business.column_names: #{Business.column_names.inspect}"
puts "--- DEBUG: businesses table columns: #{ActiveRecord::Base.connection.columns(:businesses).map { |c| [c.name, c.sql_type] }.inspect}"

# Keep the existing default business and admin
puts "Creating default tenant..."
# Be more defensive about creating default business - only create if it truly doesn't exist
default_business = Business.find_by(hostname: 'default', host_type: 'subdomain')

if default_business.nil?
  default_business = Business.new(hostname: 'default', host_type: 'subdomain')
  default_business.name = 'Default Business'
  default_business.industry = Business::SHOWCASE_INDUSTRY_MAPPINGS[:other]
  default_business.phone = '555-123-4567'
  default_business.email = 'default@example.com'
  default_business.address = '123 Main St'
  default_business.city = 'Anytown'
  default_business.state = 'CA'
  default_business.zip = '12345'
  default_business.description = 'The default business for system operations.'
  default_business.tier = :free
  default_business.active = true
  # Save without validations to bypass industry inclusion
  default_business.save!(validate: false)
  puts "Created new default tenant: #{default_business.name}"
else
  puts "Default tenant already exists: #{default_business.name} (#{default_business.hostname}) - skipping creation"
end

default_business.reload

# Create an admin user in the default tenant (SKIP in production)
if !Rails.env.production?
  puts "Creating admin user (skipped in production)..."
  admin_user = User.find_or_initialize_by(email: 'admin@example.com') do |user|
    user.business_id = default_business.id
    user.first_name = 'Admin'
    user.last_name = 'User'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = :manager
    user.active = true
    # Confirm the user immediately since this is seed data
    user.confirmed_at = Time.current
  end

  if admin_user.new_record?
    admin_user.save!
    puts "Admin user created with email: #{admin_user.email} and password: password123"
  else
    # Ensure existing admin user is confirmed
    unless admin_user.confirmed?
      admin_user.update!(confirmed_at: Time.current)
      puts "Confirmed existing admin user: #{admin_user.email}"
    end
    puts "Admin user already exists: #{admin_user.email}"
  end
else
  puts "Skipping creation of generic 'admin@example.com' in production."
end

# Add some sample data for default business
puts "Creating sample data for Default Business..."

if Rails.env.development? || Rails.env.test?
  # Create customers for Default Business
  customer_count = MINIMAL_SEED ? 1 : 3
  customer_count.times do |i|
    customer = TenantCustomer.find_or_initialize_by(
      email: "customer#{i+1}@example.com",
      business: default_business
    ) do |c|
      c.first_name = Faker::Name.first_name
      c.last_name = Faker::Name.last_name
      c.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
    end
    
    if customer.new_record?
      customer.save!
      puts "Created customer: #{customer.full_name}"
    end
  end

  # Create services for Default Business
  services = [
    { name: 'Basic Consultation', price: 75.00, duration: 60 },
    { name: 'Website Setup', price: 199.99, duration: 120 },
    { name: 'Monthly Support', price: 49.99, duration: 30 }
  ]

  services.each do |service_attrs|
    service = Service.find_or_initialize_by(
      name: service_attrs[:name],
      business: default_business
    ) do |s|
      s.price = service_attrs[:price]
      s.duration = service_attrs[:duration]
      s.description = Faker::Lorem.paragraph
    end
    
    if service.new_record?
      service.save!
      puts "Created service: #{service.name}"
    end
  end

  # Create staff members
  2.times do |i|
    staff = StaffMember.find_or_initialize_by(
      name: "Staff Member #{i+1}",
      business: default_business
    ) do |s|
      s.email = "staff#{i+1}@example.com"
      s.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
      s.active = true
      s.bio = Faker::Lorem.paragraph
    end
    
    if staff.new_record?
      staff.save!
      puts "Created staff member: #{staff.name}"
    end
  end

  # Skip booking creation in minimal mode
  unless MINIMAL_SEED
    # Create some bookings for default business
    services = Service.where(business: default_business).to_a
    customers = TenantCustomer.where(business: default_business).to_a
    staff_members = StaffMember.where(business: default_business).to_a

    if !services.empty? && !customers.empty? && !staff_members.empty?
      # Assign specific days to specific staff to avoid conflicts
      staff_days = {}
      staff_members.each_with_index do |staff, index|
        # Each staff gets different days of the week to avoid conflicts
        staff_days[staff.id] = [(index * 2) % 5 + 1, (index * 2 + 1) % 5 + 1]
      end
      
      # Each staff gets their own set of days to avoid conflicts
      staff_members.each do |staff|
        # Get the staff's assigned weekdays (1=Monday, 5=Friday)
        weekdays = staff_days[staff.id]
        
        # For each staff, try to create up to 3 bookings
        3.times do |i|
          # Use the staff's assigned weekday for this booking
          weekday = weekdays[i % weekdays.length]
          
          # Create a date in the future that falls on this weekday
          future_date = Date.today + (rand(1..14).days)
          while future_date.wday != weekday % 7
            future_date += 1.day
          end
          
          service = services.sample
          customer = customers.sample
          
          # Use different hours for each booking to avoid conflicts
          # Morning (9-11), Afternoon (12-2), Late Afternoon (3-4)
          time_slots = [
            { start_hour: 9, start_minute: 0 },
            { start_hour: 12, start_minute: 0 },
            { start_hour: 15, start_minute: 0 }
          ]
          
          slot = time_slots[i % time_slots.length]
          start_time = Time.zone.local(future_date.year, future_date.month, future_date.day, slot[:start_hour], slot[:start_minute])
          end_time = start_time + service.duration.minutes
          
          # Skip if end time is after 5 PM
          next if end_time.hour >= 17 || (end_time.hour == 17 && end_time.min > 0)
          
          # Using find_or_initialize_by with a unique combination to prevent duplicates
          booking = Booking.find_or_initialize_by(
            start_time: start_time,
            service: service,
            tenant_customer: customer,
            business: default_business
          ) do |b|
            b.end_time = end_time
            b.staff_member = staff
            b.status = [:pending, :confirmed, :completed].sample
            b.notes = Faker::Lorem.sentence
          end
          
          begin
            if booking.new_record?
              booking.save!
              puts "Created booking at #{booking.start_time.strftime('%Y-%m-%d %H:%M')} - #{booking.end_time.strftime('%H:%M')} for #{staff.name}"
            end
          rescue => e
            puts "Failed to create booking: #{e.message}"
          end
        end
      end
    end
  end
end

# Mark seeds as loaded to prevent duplicate loading
SEEDS_LOADED = true
puts "Seed data creation complete!"

# Remove redundant/conflicting business and admin user creation at the end
# # Create a default business (required for all tenancy associations)
# business = Business.find_or_initialize_by(name: "Example Business", subdomain: "example")
# if business.new_record?
#   business.save!
#   puts "Created default business: Example Business (subdomain: example)"
# end
# 
# # Create an admin user
# if Rails.env.development? || Rails.env.test?
#   AdminUser.find_or_create_by!(email: 'admin@example.com') do |admin|
#     admin.password = 'password'
#     admin.password_confirmation = 'password'
#     puts "Created admin user: admin@example.com with password: password"
#   end
# end

# Create an admin user using environment variables
admin_email = ENV['ADMIN_EMAIL']
admin_password = ENV['ADMIN_PASSWORD']

if admin_email.present? && admin_password.present?
  # Allow admin creation in any environment with proper env vars
  admin = AdminUser.find_or_initialize_by(email: admin_email) do |user|
    user.password = admin_password
    user.password_confirmation = admin_password # Assuming confirmation matches
  end

  if admin.new_record?
    admin.save!
    puts "Created admin user: #{admin_email} with password from ENV"
  else
    # Optionally update the password if it differs, or just report existence
    # admin.update(password: admin_password, password_confirmation: admin_password) if admin.valid_password?(admin_password) == false
    puts "Admin user #{admin_email} already exists."
  end
else
  puts "Skipping AdminUser creation: ADMIN_EMAIL or ADMIN_PASSWORD environment variables not set."
end

# Create initial policy versions using current Termly embeds
puts "Creating initial policy versions..."

policy_versions = [
  {
    policy_type: 'terms_of_service',
    version: 'v1.0',
    termly_embed_id: '8e1d177a-1bac-44a7-aabc-2f55625a62bc',
    active: true,
    effective_date: Date.current,
    change_summary: 'Initial Terms of Service - Platform usage rules, billing terms'
  },
  {
    policy_type: 'privacy_policy',
    version: 'v1.0',
    termly_embed_id: '34a546a3-a481-4552-85ab-8164b9014422',
    active: true,
    effective_date: Date.current,
    change_summary: 'Initial Privacy Policy - How BizBlasts handles your data'
  },
  {
    policy_type: 'acceptable_use_policy',
    version: 'v1.0',
    termly_embed_id: '5acd91e3-ec71-4968-9145-c9ea535b180e',
    active: true,
    effective_date: Date.current,
    change_summary: 'Initial Acceptable Use Policy - Platform usage guidelines'
  },
  {
    policy_type: 'return_policy',
    version: 'v1.0',
    active: true,
    effective_date: Date.current,
    change_summary: 'Initial Return Policy - Subscription cancellation/refund terms'
  }
]

policy_versions.each do |policy_attrs|
  policy = PolicyVersion.find_or_create_by(
    policy_type: policy_attrs[:policy_type],
    version: policy_attrs[:version]
  ) do |p|
    p.termly_embed_id = policy_attrs[:termly_embed_id]
    p.active = policy_attrs[:active]
    p.effective_date = policy_attrs[:effective_date]
    p.change_summary = policy_attrs[:change_summary]
  end
  
  if policy.persisted?
    puts "Created/found policy version: #{policy.policy_type} #{policy.version}"
  end
end

puts "Policy versions setup complete. Total count: #{PolicyVersion.count}"
