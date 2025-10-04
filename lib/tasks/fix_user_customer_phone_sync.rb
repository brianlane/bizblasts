#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fix phone number mismatches between User and TenantCustomer records
# Run this in production to sync User phone numbers to their linked TenantCustomer records

class UserCustomerPhoneSync
  def self.run(dry_run: true)
    puts "=== User to TenantCustomer Phone Sync #{dry_run ? '(DRY RUN)' : '(LIVE RUN)'} ==="
    puts "Starting at: #{Time.current}"
    puts

    mismatched_customers = []
    updated_count = 0
    error_count = 0

    # Find all TenantCustomers linked to Users where phone numbers differ
    TenantCustomer.joins(:user).find_each do |customer|
      user = customer.user

      # Skip if user doesn't have a phone
      next unless user.phone.present?

      # Check if phones are different
      if customer.phone != user.phone
        mismatched_customers << {
          customer_id: customer.id,
          user_id: user.id,
          business_name: customer.business.name,
          user_email: user.email,
          customer_phone: customer.phone,
          user_phone: user.phone,
          customer_opt_in: customer.phone_opt_in?,
          user_opt_in: user.respond_to?(:phone_opt_in?) ? user.phone_opt_in? : false
        }
      end
    end

    puts "Found #{mismatched_customers.count} TenantCustomers with phone mismatches:"
    puts

    mismatched_customers.each do |mismatch|
      puts "Customer ID: #{mismatch[:customer_id]} | User: #{mismatch[:user_email]} | Business: #{mismatch[:business_name]}"
      puts "  Customer Phone: #{mismatch[:customer_phone]} (opt-in: #{mismatch[:customer_opt_in]})"
      puts "  User Phone:     #{mismatch[:user_phone]} (opt-in: #{mismatch[:user_opt_in]})"
      puts

      unless dry_run
        begin
          customer = TenantCustomer.find(mismatch[:customer_id])
          user = User.find(mismatch[:user_id])

          # Use CustomerLinker to sync the data properly
          linker = CustomerLinker.new(customer.business)
          linker.sync_user_data_to_customer(user, customer)

          updated_count += 1
          puts "  ✅ UPDATED: Customer phone synced to #{user.phone}"
        rescue => e
          error_count += 1
          puts "  ❌ ERROR: #{e.message}"
        end
        puts
      end
    end

    puts "=== Summary ==="
    puts "Total mismatched records: #{mismatched_customers.count}"
    if dry_run
      puts "This was a DRY RUN - no changes were made"
      puts "Run with dry_run: false to apply changes"
    else
      puts "Records updated: #{updated_count}"
      puts "Errors encountered: #{error_count}"
    end
    puts "Completed at: #{Time.current}"
  end

  # Fix a specific user's phone sync
  def self.fix_user(user_email, dry_run: true)
    puts "=== Fixing phone sync for user: #{user_email} #{dry_run ? '(DRY RUN)' : '(LIVE RUN)'} ==="

    user = User.find_by(email: user_email)
    unless user
      puts "❌ User not found: #{user_email}"
      return
    end

    puts "User: #{user.email} | Phone: #{user.phone} | Opt-in: #{user.respond_to?(:phone_opt_in?) ? user.phone_opt_in? : 'N/A'}"
    puts

    # Find all TenantCustomer records linked to this user
    customers = TenantCustomer.where(user_id: user.id)
    puts "Found #{customers.count} linked TenantCustomer records:"
    puts

    customers.each do |customer|
      puts "Business: #{customer.business.name} | Customer Phone: #{customer.phone} | Opt-in: #{customer.phone_opt_in?}"

      if customer.phone != user.phone
        puts "  🔄 Phone mismatch detected"
        unless dry_run
          begin
            linker = CustomerLinker.new(customer.business)
            linker.sync_user_data_to_customer(user, customer)
            customer.reload
            puts "  ✅ UPDATED: Customer phone synced to #{customer.phone}"
          rescue => e
            puts "  ❌ ERROR: #{e.message}"
          end
        end
      else
        puts "  ✅ Phone numbers already match"
      end
      puts
    end

    if dry_run
      puts "This was a DRY RUN - no changes were made"
      puts "Run with dry_run: false to apply changes"
    end
  end
end

# If running as a script
if __FILE__ == $0
  # Parse command line arguments
  dry_run = !ARGV.include?('--live')
  user_email = ARGV.find { |arg| arg.include?('@') }

  if user_email
    UserCustomerPhoneSync.fix_user(user_email, dry_run: dry_run)
  else
    UserCustomerPhoneSync.run(dry_run: dry_run)
  end
end