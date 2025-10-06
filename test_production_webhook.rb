puts "=== Testing Production Webhook Behavior ==="
puts "This will help us verify if the webhook URL change is working in production"
puts

# Since we can't directly test production, let's:
# 1. Send a fresh opt-in invitation
# 2. Guide you through replying
# 3. Check for immediate results

customer = TenantCustomer.find_by(phone: '+16026866672')
business = customer&.business

if !customer || !business
  puts "❌ Test customer or business not found"
  exit 1
end

puts "Customer: #{customer.first_name} #{customer.last_name}"
puts "Business: #{business.name}"
puts "Current opt-in status: #{customer.phone_opt_in? ? 'OPTED IN' : 'NOT OPTED IN'}"
puts

# Opt out the customer for a clean test
if customer.phone_opt_in?
  customer.update!(phone_opt_in: false, phone_opt_in_at: nil)
  puts "✅ Opted out customer for clean test"
end

# Clear any recent invitations to avoid cooldown issues
SmsOptInInvitation.where(phone_number: customer.phone)
                  .where('created_at > ?', 2.hours.ago)
                  .delete_all

puts "✅ Cleared recent invitations"

# Send a fresh invitation
puts
puts "🚀 Sending fresh SMS invitation..."

result = SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)

if result[:success]
  puts "✅ SMS invitation sent successfully!"
  puts "Twilio SID: #{result[:twilio_sid]}"

  # Record the timestamp for verification
  test_timestamp = Time.current
  File.write('/tmp/webhook_test_timestamp', test_timestamp.to_f.to_s)

  puts
  puts "📱 TESTING INSTRUCTIONS:"
  puts "========================"
  puts "1. Check your phone for the NEW SMS invitation"
  puts "2. Reply 'YES' to this invitation"
  puts "3. Wait 10-15 seconds"
  puts "4. Run: bundle exec rails runner verify_webhook_results.rb"
  puts
  puts "⏰ Test started at: #{test_timestamp}"
  puts
  puts "What to expect if webhook is working:"
  puts "  ✅ You'll receive a confirmation SMS"
  puts "  ✅ Customer will be opted in"
  puts "  ✅ Webhook will process your reply"

else
  puts "❌ SMS invitation failed: #{result[:error]}"
end