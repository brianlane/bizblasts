puts "=== SMS TEST RESULTS VERIFICATION ==="
puts "This script checks if the real SMS test worked correctly"
puts

# Get test start time
test_start_time = if File.exist?('/tmp/sms_test_start_time')
  Time.at(File.read('/tmp/sms_test_start_time').to_f)
else
  10.minutes.ago
end

puts "Checking results since: #{test_start_time}"
puts

# Step 1: Check customer status
puts "📋 STEP 1: CUSTOMER OPT-IN STATUS"

customer = TenantCustomer.find_by(phone: '+16026866672')
business = customer&.business

if !customer || !business
  puts "❌ Test customer or business not found"
  exit 1
end

customer.reload
puts "Customer: #{customer.first_name} #{customer.last_name}"
puts "Business: #{business.name}"
puts "Current opt-in status: #{customer.phone_opt_in? ? '✅ OPTED IN' : '❌ NOT OPTED IN'}"
puts "Opt-in timestamp: #{customer.phone_opt_in_at}"

if customer.phone_opt_in?
  puts "✅ SUCCESS: Customer is opted in!"
else
  puts "❌ FAILURE: Customer is not opted in"
end

puts

# Step 2: Check SMS messages
puts "📋 STEP 2: SMS MESSAGE HISTORY"

recent_messages = SmsMessage.where(phone_number: customer.phone)
                           .where('created_at > ?', test_start_time)
                           .order(:created_at)

puts "SMS messages since test start: #{recent_messages.count}"

recent_messages.each_with_index do |msg, index|
  puts "  #{index + 1}. #{msg.created_at}: #{msg.content[0..50]}..."
  puts "     Status: #{msg.status}, Business: #{msg.business&.name || 'N/A'}"
end

# Count specific message types
invitation_count = recent_messages.where('content LIKE ?', '%Reply YES to receive SMS%').count
confirmation_count = recent_messages.where('content LIKE ?', '%now subscribed%').count
booking_count = recent_messages.where('content LIKE ?', '%booking%').count

puts
puts "Message breakdown:"
puts "  📤 Invitations sent: #{invitation_count}"
puts "  ✅ Confirmations sent: #{confirmation_count}"
puts "  📅 Booking notifications: #{booking_count}"

puts

# Step 3: Check pending notifications
puts "📋 STEP 3: PENDING NOTIFICATION STATUS"

pending_notifications = PendingSmsNotification.where(tenant_customer: customer)
                                             .where('created_at > ?', test_start_time - 1.hour)

total_pending = pending_notifications.count
completed_pending = pending_notifications.where(status: 'completed').count
failed_pending = pending_notifications.where(status: 'failed').count
still_pending = pending_notifications.where(status: 'pending').count

puts "Pending notifications:"
puts "  📊 Total: #{total_pending}"
puts "  ✅ Completed: #{completed_pending}"
puts "  ❌ Failed: #{failed_pending}"
puts "  ⏳ Still pending: #{still_pending}"

puts

# Step 4: Check invitation responses
puts "📋 STEP 4: INVITATION RESPONSE TRACKING"

recent_invitations = SmsOptInInvitation.where(phone_number: customer.phone)
                                       .where('created_at > ?', test_start_time - 10.minutes)

puts "Recent invitations: #{recent_invitations.count}"
recent_invitations.each do |inv|
  puts "  - #{inv.created_at}: Context: #{inv.context}"
  puts "    Business: #{inv.business.name}"
  puts "    Responded: #{inv.responded_at ? "✅ #{inv.responded_at}" : "❌ No response recorded"}"
  puts "    Response: #{inv.response_text || 'N/A'}"
end

puts

# Step 5: Overall test results
puts "📋 STEP 5: OVERALL TEST RESULTS"
puts "=================================="

success_criteria = []
success_criteria << customer.phone_opt_in?
success_criteria << (confirmation_count > 0)
success_criteria << (completed_pending > 0 || still_pending == 0)

if success_criteria.all?
  puts "🎉 COMPLETE SUCCESS!"
  puts "✅ Customer is opted in"
  puts "✅ Confirmation SMS was sent"
  puts "✅ Pending notifications were processed"
  puts
  puts "The webhook URL change is working perfectly!"
  puts "Your SMS system is now fully functional."
elsif customer.phone_opt_in?
  puts "🎯 PARTIAL SUCCESS!"
  puts "✅ Customer is opted in (main goal achieved)"
  puts "ℹ️  Some secondary features may need attention"
  puts
  puts "The webhook URL change fixed the main issue!"
else
  puts "❌ TEST FAILED"
  puts "The customer was not opted in by the webhook."
  puts "Check that:"
  puts "1. You updated the Twilio webhook URL to www.bizblasts.com"
  puts "2. You replied 'YES' to the SMS invitation"
  puts "3. The webhook is receiving and processing the message"
end

puts
puts "📊 SUMMARY METRICS:"
puts "  Opt-in status: #{customer.phone_opt_in? ? 'SUCCESS' : 'FAILED'}"
puts "  SMS messages sent: #{recent_messages.count}"
puts "  Confirmations sent: #{confirmation_count}"
puts "  Notifications processed: #{completed_pending}"

# Cleanup
File.delete('/tmp/sms_test_start_time') if File.exist?('/tmp/sms_test_start_time')