# frozen_string_literal: true

namespace :data do
  desc 'Clear corrupted encrypted phone data that cannot be decrypted'
  task clear_corrupted_phones: :environment do
    puts "=" * 80
    puts "CLEAR CORRUPTED PHONE DATA TASK"
    puts "=" * 80
    puts "This task identifies and clears phone data that cannot be decrypted"
    puts "due to encryption key mismatches."
    puts
    puts "Started at: #{Time.current}"
    puts "=" * 80
    puts

    # Counters
    users_checked = 0
    users_cleared = 0
    customers_checked = 0
    customers_cleared = 0
    errors = 0

    # Track affected records for reporting
    affected_users = []
    affected_customers = []

    puts "Phase 1: Scanning User records for corrupted phone data..."
    puts "-" * 80

    User.find_in_batches(batch_size: 100) do |batch|
      batch.each do |user|
        users_checked += 1

        begin
          # Attempt to access phone field (triggers decryption)
          _ = user.phone

          # If we get here, decryption succeeded - no action needed
          print "." if users_checked % 100 == 0 # Progress indicator

        rescue ActiveRecord::Encryption::Errors::Decryption => e
          # Decryption failed - clear the phone field
          begin
            user.update_column(:phone, nil)
            user.update_column(:phone_opt_in, false) if user.respond_to?(:phone_opt_in)
            user.update_column(:phone_opt_in_at, nil) if user.respond_to?(:phone_opt_in_at)

            users_cleared += 1
            affected_users << {
              id: user.id,
              email: user.email,
              role: user.role,
              business_id: user.business_id
            }

            puts "\n✓ Cleared phone for User ##{user.id} (#{user.email})"

          rescue => clear_error
            errors += 1
            puts "\n✗ Failed to clear phone for User ##{user.id}: #{clear_error.message}"
          end

        rescue => e
          errors += 1
          puts "\n✗ Unexpected error checking User ##{user.id}: #{e.class} - #{e.message}"
        end
      end
    end

    puts "\n"
    puts "Phase 1 Complete: Checked #{users_checked} users, cleared #{users_cleared} corrupted phone records"
    puts

    puts "Phase 2: Scanning TenantCustomer records for corrupted phone data..."
    puts "-" * 80

    TenantCustomer.find_in_batches(batch_size: 100) do |batch|
      batch.each do |customer|
        customers_checked += 1

        begin
          # Attempt to access phone field (triggers decryption)
          _ = customer.phone

          # If we get here, decryption succeeded - no action needed
          print "." if customers_checked % 100 == 0 # Progress indicator

        rescue ActiveRecord::Encryption::Errors::Decryption => e
          # Decryption failed - clear the phone field
          begin
            customer.update_column(:phone, nil)
            customer.update_column(:phone_opt_in, false)
            customer.update_column(:phone_opt_in_at, nil)

            customers_cleared += 1
            affected_customers << {
              id: customer.id,
              email: customer.email,
              business_id: customer.business_id,
              user_id: customer.user_id
            }

            puts "\n✓ Cleared phone for TenantCustomer ##{customer.id} (#{customer.email})"

          rescue => clear_error
            errors += 1
            puts "\n✗ Failed to clear phone for TenantCustomer ##{customer.id}: #{clear_error.message}"
          end

        rescue => e
          errors += 1
          puts "\n✗ Unexpected error checking TenantCustomer ##{customer.id}: #{e.class} - #{e.message}"
        end
      end
    end

    puts "\n"
    puts "Phase 2 Complete: Checked #{customers_checked} customers, cleared #{customers_cleared} corrupted phone records"
    puts

    # Final Report
    puts "=" * 80
    puts "TASK COMPLETE"
    puts "=" * 80
    puts "Finished at: #{Time.current}"
    puts
    puts "Summary:"
    puts "  Users checked:     #{users_checked}"
    puts "  Users cleared:     #{users_cleared}"
    puts "  Customers checked: #{customers_checked}"
    puts "  Customers cleared: #{customers_cleared}"
    puts "  Errors:            #{errors}"
    puts

    if users_cleared > 0
      puts "Affected Users (#{users_cleared}):"
      affected_users.each do |user|
        puts "  - User ##{user[:id]} (#{user[:email]}) - Role: #{user[:role]}, Business: #{user[:business_id]}"
      end
      puts
    end

    if customers_cleared > 0
      puts "Affected Customers (#{customers_cleared}):"
      affected_customers.each do |customer|
        linked = customer[:user_id] ? "linked to User ##{customer[:user_id]}" : "guest customer"
        puts "  - Customer ##{customer[:id]} (#{customer[:email]}) - #{linked}, Business: #{customer[:business_id]}"
      end
      puts
    end

    puts "Next Steps:"
    if users_cleared > 0 || customers_cleared > 0
      puts "  1. ✓ Corrupted phone data has been cleared"
      puts "  2. ✓ Affected users can now make bookings normally"
      puts "  3. → Users will need to re-enter their phone numbers when prompted"
      puts "  4. → Consider investigating why encryption keys changed"
      puts "  5. → Review config/credentials.yml.enc for key consistency"
    else
      puts "  ✓ No corrupted phone data found - all records are healthy!"
    end
    puts
    puts "=" * 80
  end

  desc 'Dry run - identify corrupted phone data without clearing (safe to run in production)'
  task check_corrupted_phones: :environment do
    puts "=" * 80
    puts "DRY RUN: CHECK CORRUPTED PHONE DATA"
    puts "=" * 80
    puts "This is a read-only scan that identifies corrupted phone data"
    puts "without making any changes to the database."
    puts
    puts "Started at: #{Time.current}"
    puts "=" * 80
    puts

    users_checked = 0
    users_corrupted = 0
    customers_checked = 0
    customers_corrupted = 0

    corrupted_users = []
    corrupted_customers = []

    puts "Scanning User records..."
    puts "-" * 80

    User.find_in_batches(batch_size: 100) do |batch|
      batch.each do |user|
        users_checked += 1

        begin
          _ = user.phone
          print "." if users_checked % 100 == 0
        rescue ActiveRecord::Encryption::Errors::Decryption
          users_corrupted += 1
          corrupted_users << {
            id: user.id,
            email: user.email,
            role: user.role,
            business_id: user.business_id,
            created_at: user.created_at
          }
          puts "\n⚠ Found corrupted phone: User ##{user.id} (#{user.email})"
        rescue => e
          puts "\n✗ Error checking User ##{user.id}: #{e.class}"
        end
      end
    end

    puts "\n"
    puts "Checked #{users_checked} users, found #{users_corrupted} with corrupted phone data"
    puts

    puts "Scanning TenantCustomer records..."
    puts "-" * 80

    TenantCustomer.find_in_batches(batch_size: 100) do |batch|
      batch.each do |customer|
        customers_checked += 1

        begin
          _ = customer.phone
          print "." if customers_checked % 100 == 0
        rescue ActiveRecord::Encryption::Errors::Decryption
          customers_corrupted += 1
          corrupted_customers << {
            id: customer.id,
            email: customer.email,
            business_id: customer.business_id,
            user_id: customer.user_id,
            created_at: customer.created_at
          }
          puts "\n⚠ Found corrupted phone: Customer ##{customer.id} (#{customer.email})"
        rescue => e
          puts "\n✗ Error checking Customer ##{customer.id}: #{e.class}"
        end
      end
    end

    puts "\n"
    puts "Checked #{customers_checked} customers, found #{customers_corrupted} with corrupted phone data"
    puts

    puts "=" * 80
    puts "DRY RUN COMPLETE"
    puts "=" * 80
    puts "Finished at: #{Time.current}"
    puts
    puts "Summary:"
    puts "  Users checked:          #{users_checked}"
    puts "  Users with corruption:  #{users_corrupted}"
    puts "  Customers checked:      #{customers_checked}"
    puts "  Customers with corruption: #{customers_corrupted}"
    puts

    if users_corrupted > 0
      puts "Corrupted User Records:"
      corrupted_users.each do |user|
        puts "  - User ##{user[:id]} (#{user[:email]}) - Created: #{user[:created_at]}"
      end
      puts
    end

    if customers_corrupted > 0
      puts "Corrupted Customer Records:"
      corrupted_customers.each do |customer|
        linked = customer[:user_id] ? "linked to User ##{customer[:user_id]}" : "guest"
        puts "  - Customer ##{customer[:id]} (#{customer[:email]}) - #{linked}"
      end
      puts
    end

    if users_corrupted > 0 || customers_corrupted > 0
      puts "To fix these records, run:"
      puts "  rake data:clear_corrupted_phones"
    else
      puts "✓ No corrupted phone data found!"
    end
    puts
    puts "=" * 80
  end
end
