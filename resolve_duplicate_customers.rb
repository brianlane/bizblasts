puts "=== CUSTOMERLINKER PHONE DEDUPLICATION TEST ==="
puts "Resolving duplicate TenantCustomer records using enhanced CustomerLinker..."
puts

# Find BizTest business
biztest = Business.find_by(name: "BizTest")
unless biztest
  puts "❌ BizTest business not found"
  exit
end

puts "Business: #{biztest.name} (ID: #{biztest.id})"

# Initialize CustomerLinker
linker = CustomerLinker.new(biztest)

# Test phone number that has duplicates
phone_number = "6026866672"
puts "\n=== ANALYZING DUPLICATES FOR PHONE #{phone_number} ==="

# Find customers before deduplication
customers_before = linker.send(:find_customers_by_phone, phone_number)
puts "Found #{customers_before.count} customers with phone variations:"

customers_before.each do |customer|
  puts "  Customer #{customer.id}:"
  puts "    Name: #{customer.first_name} #{customer.last_name}"
  puts "    Email: #{customer.email}"
  puts "    Phone: #{customer.phone}"
  puts "    User ID: #{customer.user_id || 'None'}"
  puts "    SMS Opt-in: #{customer.phone_opt_in?}"
  puts "    Created: #{customer.created_at}"
  puts "    Completeness Score: #{linker.send(:customer_completeness_score, customer)}"
  puts
end

if customers_before.count <= 1
  puts "✅ No duplicates found - nothing to resolve"
  exit
end

# Show which customer would be selected as canonical
canonical = linker.send(:select_canonical_customer, customers_before)
puts "=== CANONICAL CUSTOMER SELECTION ==="
puts "Selected Customer #{canonical.id} as canonical:"
puts "  Reason: #{canonical.user_id ? 'User-linked' : 'Most complete/oldest'}"
puts "  Name: #{canonical.first_name} #{canonical.last_name}"
puts "  Email: #{canonical.email}"
puts "  Phone: #{canonical.phone}"
puts

# Check related records that would be migrated
duplicate_ids = customers_before.map(&:id) - [canonical.id]
puts "=== RELATED RECORDS TO MIGRATE ==="

# Check Bookings
bookings = Booking.where(tenant_customer_id: duplicate_ids)
puts "Bookings to migrate: #{bookings.count}"

# Check SMS Messages
sms_messages = SmsMessage.where(tenant_customer_id: duplicate_ids)
puts "SMS Messages to migrate: #{sms_messages.count}"

# Check SMS Invitations
sms_invitations = SmsOptInInvitation.where(tenant_customer_id: duplicate_ids)
puts "SMS Invitations to migrate: #{sms_invitations.count}"

puts "\n=== PERFORMING DEDUPLICATION ==="
puts "🔧 Resolving phone duplicates..."

# Actually resolve the duplicates
canonical_customer = linker.resolve_phone_duplicates(phone_number)

if canonical_customer
  puts "✅ Successfully resolved duplicates!"
  puts "Canonical Customer: #{canonical_customer.id} (#{canonical_customer.first_name} #{canonical_customer.last_name})"
  puts "Phone: #{canonical_customer.phone}"
  puts "SMS Opt-in: #{canonical_customer.phone_opt_in?}"
  puts "SMS Opt-in timestamp: #{canonical_customer.phone_opt_in_at}"

  puts "\n=== VERIFICATION ==="
  # Verify only one customer remains
  remaining_customers = linker.send(:find_customers_by_phone, phone_number)
  puts "Customers remaining: #{remaining_customers.count}"

  if remaining_customers.count == 1
    puts "✅ Deduplication successful - only canonical customer remains"

    # Check if SMS opt-in was preserved
    if canonical_customer.phone_opt_in?
      puts "✅ SMS opt-in status preserved"
      puts "🎉 Customer should now receive SMS notifications!"
    else
      puts "⚠️  SMS opt-in not active - may need manual opt-in"
    end
  else
    puts "❌ Deduplication may have failed - multiple customers still exist"
  end
else
  puts "❌ Failed to resolve duplicates"
end

puts "\n=== NEXT STEPS ==="
puts "1. Customer #{canonical_customer&.id} should now receive SMS notifications"
puts "2. Book a test service to verify SMS delivery"
puts "3. Check logs for successful SMS sending (no 'Customer X not opted in' messages)"