#!/usr/bin/env ruby
# Debug script for webhook processing failures

puts "=== Webhook Processing Debug Script ==="
puts "This script tests all components of the SMS opt-in webhook flow"
puts

# Find the test customer
customer = TenantCustomer.find(1)
business = customer.business
phone = customer.phone

puts "Customer: #{customer.first_name} #{customer.last_name}"
puts "Phone: #{phone}"
puts "Business: #{business.name}"
puts "Currently opted in: #{customer.phone_opt_in?}"
puts

# Test 1: Business lookup for auto-reply
puts "=== Test 1: Business Lookup for Auto-Reply ==="
controller = Webhooks::TwilioController.new
begin
  found_business = controller.send(:find_business_for_auto_reply, phone)
  if found_business
    puts "✅ Business found: #{found_business.name} (ID: #{found_business.id})"
  else
    puts "❌ No business found for auto-reply"
  end
rescue => e
  puts "❌ find_business_for_auto_reply failed: #{e.message}"
  puts "   #{e.backtrace.first}"
end
puts

# Test 2: SmsService.send_message with detailed error handling
puts "=== Test 2: SMS Service Direct Test ==="
if found_business
  begin
    result = SmsService.send_message(phone, 'Test confirmation message', {
      business_id: found_business.id,
      tenant_customer_id: customer.id,
      auto_reply: true
    })

    if result[:success]
      puts "✅ SMS send successful"
      puts "   Message sent with result: #{result}"
    else
      puts "❌ SMS send failed"
      puts "   Error: #{result[:error]}"
      puts "   Full result: #{result}"
    end
  rescue => e
    puts "❌ SmsService.send_message raised exception: #{e.message}"
    puts "   Exception class: #{e.class}"
    puts "   Backtrace: #{e.backtrace.first(3).join('\n   ')}"
  end
else
  puts "❌ Skipping SMS test - no business found"
end
puts

# Test 3: Pending notifications check
puts "=== Test 3: Pending Notifications ==="
pending_notifications = PendingSmsNotification.where(tenant_customer: customer)
puts "Total pending notifications: #{pending_notifications.count}"

if pending_notifications.any?
  pending_notifications.each do |notification|
    puts "  - #{notification.notification_type}: #{notification.status} (#{notification.created_at})"
  end
else
  puts "No pending notifications found"
end
puts

# Test 4: Recent SMS messages analysis
puts "=== Test 4: Recent SMS Messages Analysis ==="
recent_sms = SmsMessage.where(phone_number: phone)
                      .where('created_at > ?', 24.hours.ago)
                      .order(created_at: :desc)

puts "Recent SMS messages (last 24 hours): #{recent_sms.count}"
recent_sms.each do |sms|
  puts "  - #{sms.created_at}: #{sms.content[0..60]}..."
  puts "    Status: #{sms.status}"

  # Check if direction column exists
  begin
    puts "    Direction: #{sms.direction}"
  rescue NoMethodError
    puts "    Direction: N/A (column doesn't exist)"
  end
end
puts

# Test 5: Webhook signature verification status
puts "=== Test 5: Webhook Configuration ==="
verify_enabled = controller.send(:verify_webhook_signature?)
puts "Signature verification enabled: #{verify_enabled}"
puts "TWILIO_VERIFY_SIGNATURES env var: #{ENV['TWILIO_VERIFY_SIGNATURES'].inspect}"
puts

# Test 6: Business SMS capabilities
puts "=== Test 6: Business SMS Capabilities ==="
puts "Business SMS enabled: #{business.sms_enabled?}"
puts "Business can send SMS: #{business.can_send_sms?}"
puts

puts "=== Summary and Diagnosis ==="
puts "Based on the tests above:"
puts "1. If business lookup failed -> Check find_business_for_auto_reply logic"
puts "2. If SMS send failed -> Check SmsService configuration and Twilio credentials"
puts "3. If no confirmation sent but customer opted in -> Silent error in send_auto_reply"
puts "4. If pending notifications exist -> Check notification replay job"
puts

puts "=== Next Steps ==="
puts "1. Fix any errors identified above"
puts "2. Re-enable signature verification with proper URL handling"
puts "3. Test end-to-end flow again"
puts "4. Add better error logging to prevent silent failures"