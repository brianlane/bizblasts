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
require 'faker'

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

# Keep the existing default company and admin
puts "Creating default tenant..."
default_company = Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
default_company.reload # Explicitly reload
puts "Default tenant created: #{default_company.name} (#{default_company.subdomain}) ID: #{default_company.id}"

# Create an admin user in the default tenant
puts "Creating admin user..."
admin_user = User.find_or_initialize_by(email: 'admin@example.com') do |user|
  user.company_id = default_company.id # Assign by ID
  user.password = 'password123'
  # user.company = default_company # Original line
end

if admin_user.new_record?
  admin_user.save!
  puts "Admin user created with email: #{admin_user.email} and password: password123"
else
  puts "Admin user already exists: #{admin_user.email}"
end

# Add some sample data for default company
puts "Creating sample data for Default Company..."

# Create customers for Default Company
customer_count = MINIMAL_SEED ? 1 : 3
customer_count.times do |i|
  customer = Customer.find_or_initialize_by(
    email: "customer#{i+1}@example.com",
    company: default_company
  ) do |c|
    c.name = Faker::Name.name
    c.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
  end
  
  if customer.new_record?
    customer.save!
    puts "Created customer: #{customer.name}"
  end
end

# Create services for Default Company
services = [
  { name: 'Basic Consultation', price: 75.00, duration_minutes: 60 },
  { name: 'Website Setup', price: 199.99, duration_minutes: 120 },
  { name: 'Monthly Support', price: 49.99, duration_minutes: 30 }
]

services.each do |service_attrs|
  service = Service.find_or_initialize_by(
    name: service_attrs[:name],
    company: default_company
  ) do |s|
    s.price = service_attrs[:price]
    s.duration_minutes = service_attrs[:duration_minutes]
    s.description = Faker::Lorem.paragraph
  end
  
  if service.new_record?
    service.save!
    puts "Created service: #{service.name}"
  end
end

# Create service providers
2.times do |i|
  provider = ServiceProvider.find_or_initialize_by(
    name: "Provider #{i+1}",
    company: default_company
  ) do |p|
    p.email = "provider#{i+1}@example.com"
    p.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
    p.active = true
    
    # Add default availability - working hours 9 AM to 5 PM Monday through Friday
    p.availability = {
      "monday" => [{ "start" => "09:00", "end" => "17:00" }],
      "tuesday" => [{ "start" => "09:00", "end" => "17:00" }],
      "wednesday" => [{ "start" => "09:00", "end" => "17:00" }],
      "thursday" => [{ "start" => "09:00", "end" => "17:00" }],
      "friday" => [{ "start" => "09:00", "end" => "17:00" }],
      "saturday" => [],
      "sunday" => []
    }
  end
  
  if provider.new_record?
    provider.save!
    puts "Created service provider: #{provider.name}"
  end
end

# Skip appointment creation in minimal mode
unless MINIMAL_SEED
  # Create some appointments for default company
  services = Service.where(company: default_company).to_a
  customers = Customer.where(company: default_company).to_a
  providers = ServiceProvider.where(company: default_company).to_a

  if !services.empty? && !customers.empty? && !providers.empty?
    # Assign specific days to specific providers to avoid conflicts
    provider_days = {}
    providers.each_with_index do |provider, index|
      # Each provider gets different days of the week to avoid conflicts
      provider_days[provider.id] = [(index * 2) % 5 + 1, (index * 2 + 1) % 5 + 1]
    end
    
    # Each provider gets their own set of days to avoid conflicts
    providers.each do |provider|
      # Get the provider's assigned weekdays (1=Monday, 5=Friday)
      weekdays = provider_days[provider.id]
      
      # For each provider, try to create up to 3 appointments
      3.times do |i|
        # Use the provider's assigned weekday for this appointment
        weekday = weekdays[i % weekdays.length]
        
        # Create a date in the future that falls on this weekday
        future_date = Date.today + (rand(1..14).days)
        while future_date.wday != weekday % 7
          future_date += 1.day
        end
        
        service = services.sample
        customer = customers.sample
        
        # Use different hours for each appointment to avoid conflicts
        # Morning (9-11), Afternoon (12-2), Late Afternoon (3-4)
        time_slots = [
          { start_hour: 9, start_minute: 0 },
          { start_hour: 12, start_minute: 0 },
          { start_hour: 15, start_minute: 0 }
        ]
        
        slot = time_slots[i % time_slots.length]
        start_time = Time.zone.local(future_date.year, future_date.month, future_date.day, slot[:start_hour], slot[:start_minute])
        end_time = start_time + service.duration_minutes.minutes
        
        # Skip if end time is after 5 PM
        next if end_time.hour >= 17 || (end_time.hour == 17 && end_time.min > 0)
        
        # Using find_or_initialize_by with a unique combination to prevent duplicates
        appointment = Appointment.find_or_initialize_by(
          start_time: start_time,
          service: service,
          customer: customer,
          company: default_company
        ) do |a|
          a.end_time = end_time
          a.service_provider = provider
          a.status = ['scheduled', 'completed', 'cancelled'].sample
          a.price = service.price
        end
        
        begin
          if appointment.new_record?
            appointment.save!
            puts "Created appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')} - #{appointment.end_time.strftime('%H:%M')} for #{provider.name}"
          end
        rescue => e
          puts "Failed to create appointment: #{e.message}"
        end
      end
    end
  end

  # Skip additional companies in minimal seed mode
  company_data = [
    {
      name: "Larry's Landscaping",
      subdomain: "larrys",
      industry: "Landscaping",
      services: [
        { name: 'Lawn Mowing', price: 50.00, duration_minutes: 60 },
        { name: 'Garden Design', price: 150.00, duration_minutes: 120 },
        { name: 'Tree Trimming', price: 200.00, duration_minutes: 180 },
        { name: 'Irrigation Installation', price: 300.00, duration_minutes: 240 }
      ]
    },
    {
      name: "Pete's Pool Service",
      subdomain: "petes",
      industry: "Pool Service",
      services: [
        { name: 'Pool Cleaning', price: 75.00, duration_minutes: 60 },
        { name: 'Filter Change', price: 100.00, duration_minutes: 90 },
        { name: 'Chemical Treatment', price: 50.00, duration_minutes: 30 },
        { name: 'Equipment Repair', price: 150.00, duration_minutes: 120 }
      ]
    }
  ]

  company_data.each do |company_info|
    puts "Creating #{company_info[:name]}..."
    company = Company.find_or_create_by!(name: company_info[:name], subdomain: company_info[:subdomain])
    
    # Create owner/admin user
    email = "owner@#{company_info[:subdomain]}.com"
    owner = User.find_or_initialize_by(email: email) do |user|
      user.password = 'password123'
      user.company = company
    end
    
    if owner.new_record?
      owner.save!
      puts "Created owner user: #{email} with password: password123"
    end
    
    # Create staff users
    2.times do |i|
      staff_email = "staff#{i+1}@#{company_info[:subdomain]}.com"
      staff = User.find_or_initialize_by(email: staff_email) do |user|
        user.password = 'password123'
        user.company = company
      end
      
      if staff.new_record?
        staff.save!
        puts "Created staff user: #{staff_email}"
      end
    end
    
    # Create customers (more for each business)
    8.times do |i|
      customer = Customer.find_or_initialize_by(
        email: "customer#{i+1}@#{company_info[:subdomain]}.example.com",
        company: company
      ) do |c|
        c.name = Faker::Name.name
        c.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
      end
      
      if customer.new_record?
        customer.save!
        puts "Created customer: #{customer.name}"
      end
    end
    
    # Create services
    company_info[:services].each do |service_attrs|
      service = Service.find_or_initialize_by(
        name: service_attrs[:name],
        company: company
      ) do |s|
        s.price = service_attrs[:price]
        s.duration_minutes = service_attrs[:duration_minutes]
        s.description = Faker::Lorem.paragraph
      end
      
      if service.new_record?
        service.save!
        puts "Created service: #{service.name}"
      end
    end
    
    # Create service providers
    provider_count = company_info[:name].include?('Landscaping') ? 4 : 3
    provider_count.times do |i|
      provider_name = Faker::Name.name
      provider = ServiceProvider.find_or_initialize_by(
        name: provider_name,
        company: company
      ) do |p|
        p.email = "provider#{i+1}@#{company_info[:subdomain]}.com"
        p.phone = "+1-#{rand(100..999)}-#{rand(100..999)}-#{rand(1000..9999)}"
        p.active = true
        
        # Add default availability - working hours 9 AM to 5 PM Monday through Friday
        p.availability = {
          "monday" => [{ "start" => "09:00", "end" => "17:00" }],
          "tuesday" => [{ "start" => "09:00", "end" => "17:00" }],
          "wednesday" => [{ "start" => "09:00", "end" => "17:00" }],
          "thursday" => [{ "start" => "09:00", "end" => "17:00" }],
          "friday" => [{ "start" => "09:00", "end" => "17:00" }],
          "saturday" => [],
          "sunday" => []
        }
      end
      
      if provider.new_record?
        provider.save!
        puts "Created service provider: #{provider.name}"
      end
    end
    
    # Create appointments (past, present, future)
    services = Service.where(company: company).to_a
    customers = Customer.where(company: company).to_a
    providers = ServiceProvider.where(company: company).to_a
    
    if !services.empty? && !customers.empty? && !providers.empty?
      # Assign specific days to specific providers to avoid conflicts
      provider_days = {}
      providers.each_with_index do |provider, index|
        # Each provider gets different days of the week to avoid conflicts
        provider_days[provider.id] = [(index * 2) % 5 + 1, (index * 2 + 1) % 5 + 1]
      end
      
      # Create past appointments (some completed, some cancelled)
      # Each provider gets their own set of days to avoid conflicts
      providers.each do |provider|
        # Get the provider's assigned weekdays (1=Monday, 5=Friday)
        weekdays = provider_days[provider.id]
        
        # For each provider, try to create up to 3 past appointments
        3.times do |i|
          # Use the provider's assigned weekday for this appointment
          weekday = weekdays[i % weekdays.length]
          
          # Create a date in the past that falls on this weekday
          past_date = Date.today - (rand(1..14).days)
          while past_date.wday != weekday % 7
            past_date -= 1.day
          end
          
          service = services.sample
          customer = customers.sample
          status = ['completed', 'cancelled', 'no-show'].sample
          
          # Use different hours for each appointment to avoid conflicts
          # Morning (9-11), Afternoon (12-2), Late Afternoon (3-4)
          time_slots = [
            { start_hour: 9, start_minute: 0 },
            { start_hour: 12, start_minute: 0 },
            { start_hour: 15, start_minute: 0 }
          ]
          
          slot = time_slots[i % time_slots.length]
          start_time = Time.zone.local(past_date.year, past_date.month, past_date.day, slot[:start_hour], slot[:start_minute])
          end_time = start_time + service.duration_minutes.minutes
          
          # Skip if end time is after 5 PM
          next if end_time.hour >= 17 || (end_time.hour == 17 && end_time.min > 0)
          
          # Using a unique combination to prevent duplicates
          appointment = Appointment.find_or_initialize_by(
            start_time: start_time,
            service: service,
            customer: customer,
            company: company
          ) do |a|
            a.end_time = end_time
            a.service_provider = provider
            a.status = status
            a.price = service.price
            a.paid = status == 'completed' ? [true, false].sample : false
          end
          
          begin
            if appointment.new_record?
              appointment.save!
              puts "Created past appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')} - #{appointment.end_time.strftime('%H:%M')} for #{provider.name}"
            end
          rescue => e
            puts "Failed to create appointment: #{e.message}"
          end
        end
        
        # Create upcoming appointments (all scheduled)
        # For each provider, try to create up to 3 future appointments
        3.times do |i|
          # Use the provider's assigned weekday for this appointment
          weekday = weekdays[i % weekdays.length]
          
          # Create a date in the future that falls on this weekday
          future_date = Date.today + (rand(1..14).days)
          while future_date.wday != weekday % 7
            future_date += 1.day
          end
          
          service = services.sample
          customer = customers.sample
          
          # Use different hours for each appointment to avoid conflicts
          # Morning (9-11), Afternoon (12-2), Late Afternoon (3-4)
          time_slots = [
            { start_hour: 9, start_minute: 0 },
            { start_hour: 12, start_minute: 0 },
            { start_hour: 15, start_minute: 0 }
          ]
          
          slot = time_slots[i % time_slots.length]
          start_time = Time.zone.local(future_date.year, future_date.month, future_date.day, slot[:start_hour], slot[:start_minute])
          end_time = start_time + service.duration_minutes.minutes
          
          # Skip if end time is after 5 PM
          next if end_time.hour >= 17 || (end_time.hour == 17 && end_time.min > 0)
          
          # Using a unique combination to prevent duplicates
          appointment = Appointment.find_or_initialize_by(
            start_time: start_time,
            service: service,
            customer: customer,
            company: company
          ) do |a|
            a.end_time = end_time
            a.service_provider = provider
            a.status = 'scheduled'
            a.price = service.price
            a.paid = [true, false].sample
          end
          
          begin
            if appointment.new_record?
              appointment.save!
              puts "Created upcoming appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')} - #{appointment.end_time.strftime('%H:%M')} for #{provider.name}"
            end
          rescue => e
            puts "Failed to create appointment: #{e.message}"
          end
        end
      end
    end
  end
end

puts "Database seeding completed successfully!"

# Remove redundant/conflicting company and admin user creation at the end
# # Create a default company (required for all tenancy associations)
# company = Company.find_or_initialize_by(name: "Example Company", subdomain: "example")
# if company.new_record?
#   company.save!
#   puts "Created default company: Example Company (subdomain: example)"
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
  if Rails.env.development? || Rails.env.test? # Ensure this only runs in dev/test
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
  end
else
  puts "Skipping AdminUser creation: ADMIN_EMAIL or ADMIN_PASSWORD environment variables not set."
end

SEEDS_LOADED = true # Mark as loaded
