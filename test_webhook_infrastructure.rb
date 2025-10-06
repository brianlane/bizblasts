puts "=== WEBHOOK INFRASTRUCTURE TEST ==="
puts "Testing if webhooks can reach the Rails application"
puts

# 1. Find a customer to test with
puts "📋 FINDING TEST CUSTOMER:"
puts "========================"

# Look for customer 8 (phone 6026866672) from the logs
test_customer = TenantCustomer.find_by(phone: '+16026866672') ||
                TenantCustomer.find_by(phone: '6026866672') ||
                TenantCustomer.where("phone LIKE ?", "%6026866672%").first

if test_customer
  puts "✅ Found test customer: #{test_customer.first_name} #{test_customer.last_name}"
  puts "   Phone: #{test_customer.phone}"
  puts "   Business: #{test_customer.business.name} (ID: #{test_customer.business_id})"
  puts "   Current SMS opt-in: #{test_customer.phone_opt_in?}"
else
  puts "❌ Test customer not found. Using first available customer with phone."
  test_customer = TenantCustomer.where.not(phone: [nil, '']).first

  if test_customer
    puts "✅ Using alternative customer: #{test_customer.first_name} #{test_customer.last_name}"
    puts "   Phone: #{test_customer.phone}"
    puts "   Business: #{test_customer.business.name} (ID: #{test_customer.business_id})"
  else
    puts "❌ No customers with phone numbers found"
    exit
  end
end

business = test_customer.business

puts "\n📋 BUSINESS SMS CONFIGURATION:"
puts "=============================="
puts "Business: #{business.name}"
puts "SMS enabled: #{business.sms_enabled?}"
puts "Tier: #{business.tier}"
puts "Can send SMS: #{business.can_send_sms?}"

puts "\n📋 CUSTOMER SMS STATUS:"
puts "======================"
puts "Phone opt-in: #{test_customer.phone_opt_in?}"
puts "Can receive booking SMS: #{test_customer.can_receive_sms?(:booking)}"

# Check recent SMS activity
puts "\n📋 RECENT SMS ACTIVITY:"
puts "======================"
recent_messages = SmsMessage.where(phone_number: test_customer.phone).order(created_at: :desc).limit(3)
puts "Recent SMS messages: #{recent_messages.count}"
recent_messages.each_with_index do |msg, idx|
  puts "  #{idx + 1}. #{msg.created_at}: #{msg.content[0..50]}... (Status: #{msg.status})"
end

recent_invitations = SmsOptInInvitation.where(phone_number: test_customer.phone).order(created_at: :desc).limit(3)
puts "Recent invitations: #{recent_invitations.count}"
recent_invitations.each_with_index do |inv, idx|
  puts "  #{idx + 1}. #{inv.created_at}: #{inv.context} to #{inv.business.name}"
end

puts "\n🧪 TESTING WEBHOOK INFRASTRUCTURE:"
puts "=================================="

# Before sending invitation, check if we can track webhook calls
puts "Current time: #{Time.current}"
puts "Monitor production logs for [WEBHOOK_DEBUG] entries after sending invitation..."

# Send fresh invitation
puts "\n📤 SENDING FRESH SMS INVITATION:"
puts "==============================="

begin
  # Temporarily reset opt-in status to test fresh invitation
  if test_customer.phone_opt_in?
    puts "Customer currently opted in. Temporarily opting out for fresh test..."
    test_customer.update!(phone_opt_in: false, phone_opt_in_at: nil)
  end

  result = SmsService.send_opt_in_invitation(test_customer, business, :booking_confirmation)

  puts "Invitation sent: #{result[:success]}"
  if result[:error]
    puts "Error: #{result[:error]}"
  else
    puts "✅ SMS invitation sent successfully!"
    puts "📱 Reply 'YES' to #{ENV['TWILIO_PHONE_NUMBER']} to test webhook"
    puts ""
    puts "🔍 MONITORING INSTRUCTIONS:"
    puts "==========================="
    puts "1. Wait for SMS to arrive on phone #{test_customer.phone}"
    puts "2. Reply 'YES' to the SMS"
    puts "3. Immediately check production logs for '[WEBHOOK_DEBUG]' entries"
    puts "4. If no debug logs appear within 30 seconds:"
    puts "   → Webhooks are not reaching Rails application"
    puts "   → Check Twilio webhook URL configuration"
    puts "   → Check infrastructure/proxy blocking"
    puts ""
    puts "Expected webhook flow:"
    puts "  Twilio → POST https://www.bizblasts.com/webhooks/twilio/inbound"
    puts "  Rails → [WEBHOOK_DEBUG] logs should appear"
    puts "  Customer → Should be opted in automatically"
  end
rescue => e
  puts "❌ Error sending invitation: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join(', ')}"
end

puts "\n⏰ WEBHOOK TIMING TEST:"
puts "======================"
puts "Current timestamp: #{Time.current.iso8601}"
puts "If you reply 'YES' now, webhook should arrive within 5-10 seconds"
puts "Check logs immediately after replying for any webhook activity"

puts "\n💡 TROUBLESHOOTING GUIDE:"
puts "========================"
puts "IF NO [WEBHOOK_DEBUG] LOGS APPEAR:"
puts "→ Issue: Webhooks not reaching Rails application"
puts "→ Check: Twilio console webhook URL configuration"
puts "→ Check: Infrastructure blocking (firewall, proxy, load balancer)"
puts "→ Check: DNS resolution for www.bizblasts.com"
puts ""
puts "IF [WEBHOOK_DEBUG] LOGS APPEAR BUT VALIDATION FAILS:"
puts "→ Issue: Signature verification problem"
puts "→ Check: URL mismatch in signature validation"
puts "→ Check: TWILIO_AUTH_TOKEN configuration"
puts "→ Check: Request body modification by middleware"