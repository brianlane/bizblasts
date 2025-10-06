puts "=== Webhook Results Verification ==="
puts "Checking if the webhook processed your YES reply correctly"
puts

# Get the test timestamp
test_start_time = if File.exist?('/tmp/webhook_test_timestamp')
  Time.at(File.read('/tmp/webhook_test_timestamp').to_f)
else
  puts "❌ No test timestamp found. Did you run test_production_webhook.rb first?"
  exit 1
end

puts "Test started at: #{test_start_time}"
puts "Checking activity since then..."
puts

# Check customer status
customer = TenantCustomer.find_by(phone: '+16026866672')
if !customer
  puts "❌ Customer not found"
  exit 1
end

customer.reload
puts "📊 CUSTOMER STATUS:"
puts "  Name: #{customer.first_name} #{customer.last_name}"
puts "  Phone: #{customer.phone}"
puts "  Opted in: #{customer.phone_opt_in? ? '✅ YES' : '❌ NO'}"
puts "  Opt-in timestamp: #{customer.phone_opt_in_at || 'None'}"

# Check if opt-in timestamp is after our test
if customer.phone_opt_in? && customer.phone_opt_in_at && customer.phone_opt_in_at > test_start_time
  puts "  🎉 SUCCESS: Customer was opted in AFTER the test started!"
  webhook_working = true
else
  puts "  ⚠️  Customer opt-in status unchanged since test"
  webhook_working = false
end

puts

# Check for new SMS messages
puts "📱 SMS MESSAGE ACTIVITY:"
new_messages = SmsMessage.where(phone_number: customer.phone)
                         .where('created_at > ?', test_start_time)
                         .order(:created_at)

puts "  New SMS messages since test: #{new_messages.count}"

new_messages.each_with_index do |msg, index|
  puts "    #{index + 1}. #{msg.created_at}: #{msg.content[0..60]}..."
  puts "       Status: #{msg.status}, Business: #{msg.business&.name}"
end

# Count specific message types
confirmation_messages = new_messages.where('content LIKE ? OR content LIKE ?', '%subscribed%', '%now subscribed%').count
auto_reply_messages = new_messages.count

puts "  Confirmation messages: #{confirmation_messages}"

if confirmation_messages > 0
  puts "  🎉 SUCCESS: Confirmation SMS was sent!"
  confirmation_working = true
else
  puts "  ⚠️  No confirmation SMS detected"
  confirmation_working = false
end

puts

# Check invitation responses
puts "📝 INVITATION RESPONSE TRACKING:"
recent_invitations = SmsOptInInvitation.where(phone_number: customer.phone)
                                       .where('created_at > ?', test_start_time - 5.minutes)

puts "  Invitations since test: #{recent_invitations.count}"
recent_invitations.each do |inv|
  puts "    - Sent: #{inv.created_at}"
  puts "      Business: #{inv.business.name}"
  puts "      Responded at: #{inv.responded_at || 'Not recorded'}"
  puts "      Response: #{inv.response_text || 'None'}"
end

response_recorded = recent_invitations.any? { |inv| inv.responded_at.present? }

if response_recorded
  puts "  ✅ SUCCESS: Response was recorded!"
  response_working = true
else
  puts "  ⚠️  No response recorded in invitation tracking"
  response_working = false
end

puts

# Overall assessment
puts "🏆 OVERALL WEBHOOK TEST RESULTS:"
puts "=================================="

if webhook_working && confirmation_working
  puts "🎉 COMPLETE SUCCESS!"
  puts "✅ Webhook processed your YES reply"
  puts "✅ Customer was opted in"
  puts "✅ Confirmation SMS was sent"
  puts
  puts "The webhook URL change is working perfectly!"
  puts "Your SMS system is now fully functional."

elsif webhook_working
  puts "🎯 PARTIAL SUCCESS!"
  puts "✅ Webhook processed your YES reply (customer opted in)"
  puts "ℹ️  Some confirmation messaging may need attention"
  puts
  puts "The main webhook issue is FIXED!"

else
  puts "❌ WEBHOOK STILL NOT WORKING"
  puts "The customer was not opted in by the webhook."
  puts
  puts "Possible issues:"
  puts "1. Webhook signature verification failing in production"
  puts "2. Network/routing issues"
  puts "3. Application errors in production"
  puts
  puts "Next steps:"
  puts "- Check production logs for webhook errors"
  puts "- Consider temporarily disabling signature verification"
  puts "- Verify production environment configuration"
end

puts
puts "📊 DETAILED METRICS:"
puts "  Customer opted in: #{webhook_working ? 'SUCCESS' : 'FAILED'}"
puts "  Confirmation sent: #{confirmation_working ? 'SUCCESS' : 'FAILED'}"
puts "  Response recorded: #{response_working ? 'SUCCESS' : 'FAILED'}"
puts "  SMS messages created: #{new_messages.count}"

# Cleanup
File.delete('/tmp/webhook_test_timestamp') if File.exist?('/tmp/webhook_test_timestamp')