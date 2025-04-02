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

puts "Seeding database with sample data..."

# Keep the existing default company and admin
puts "Creating default tenant..."
default_company = Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
puts "Default tenant created: #{default_company.name} (#{default_company.subdomain})"

# Create an admin user in the default tenant
puts "Creating admin user..."
admin_user = User.find_or_initialize_by(email: 'admin@example.com') do |user|
  user.password = 'password123'
  user.company = default_company
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
3.times do |i|
  customer = Customer.find_or_initialize_by(
    email: "customer#{i+1}@example.com",
    company: default_company
  ) do |c|
    c.name = Faker::Name.name
    c.phone = Faker::PhoneNumber.phone_number
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
    p.phone = Faker::PhoneNumber.phone_number
    p.active = true
  end
  
  if provider.new_record?
    provider.save!
    puts "Created service provider: #{provider.name}"
  end
end

# Create some appointments
services = Service.where(company: default_company).to_a
customers = Customer.where(company: default_company).to_a
providers = ServiceProvider.where(company: default_company).to_a

if !services.empty? && !customers.empty? && !providers.empty?
  5.times do |i|
    start_time = Faker::Time.between(from: 1.day.from_now, to: 2.weeks.from_now)
    service = services.sample
    customer = customers.sample
    
    # Using find_or_initialize_by with a unique combination to prevent duplicates
    appointment = Appointment.find_or_initialize_by(
      start_time: start_time,
      service: service,
      customer: customer,
      company: default_company
    ) do |a|
      a.end_time = start_time + service.duration_minutes.minutes
      a.service_provider = providers.sample
      a.client_name = customer.name
      a.client_email = customer.email
      a.client_phone = customer.phone
      a.status = ['scheduled', 'completed', 'cancelled'].sample
      a.price = service.price
    end
    
    if appointment.new_record?
      appointment.save!
      puts "Created appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')}"
    end
  end
end

# Create sample tenant companies with their own data
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
      c.phone = Faker::PhoneNumber.phone_number
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
      p.phone = Faker::PhoneNumber.phone_number
      p.active = true
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
    # Past appointments (some completed, some cancelled)
    10.times do
      start_time = Faker::Time.between(from: 2.weeks.ago, to: 1.day.ago)
      service = services.sample
      customer = customers.sample
      status = ['completed', 'cancelled', 'no-show'].sample
      
      # Using a unique combination to prevent duplicates
      appointment = Appointment.find_or_initialize_by(
        start_time: start_time,
        service: service,
        customer: customer,
        company: company
      ) do |a|
        a.end_time = start_time + service.duration_minutes.minutes
        a.service_provider = providers.sample
        a.client_name = customer.name
        a.client_email = customer.email
        a.client_phone = customer.phone
        a.status = status
        a.price = service.price
        a.paid = status == 'completed' ? [true, false].sample : false
      end
      
      if appointment.new_record?
        appointment.save!
        puts "Created past appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')}"
      end
    end
    
    # Future appointments (all scheduled)
    15.times do
      start_time = Faker::Time.between(from: Time.now, to: 3.weeks.from_now)
      service = services.sample
      customer = customers.sample
      
      appointment = Appointment.find_or_initialize_by(
        start_time: start_time,
        service: service,
        customer: customer,
        company: company
      ) do |a|
        a.end_time = start_time + service.duration_minutes.minutes
        a.service_provider = providers.sample
        a.client_name = customer.name
        a.client_email = customer.email
        a.client_phone = customer.phone
        a.status = 'scheduled'
        a.price = service.price
      end
      
      if appointment.new_record?
        appointment.save!
        puts "Created future appointment at #{appointment.start_time.strftime('%Y-%m-%d %H:%M')}"
      end
    end
  end
end

puts "Database seeding completed successfully!"

# Create a default company (required for all tenancy associations)
company = Company.find_or_initialize_by(name: "Example Company", subdomain: "example")
if company.new_record?
  company.save!
  puts "Created default company: Example Company (subdomain: example)"
end

# Create an admin user
if Rails.env.development? || Rails.env.test?
  AdminUser.find_or_create_by!(email: 'admin@example.com') do |admin|
    admin.password = 'password'
    admin.password_confirmation = 'password'
    puts "Created admin user: admin@example.com with password: password"
  end
end