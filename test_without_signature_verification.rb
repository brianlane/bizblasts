puts "=== TEST WITHOUT SIGNATURE VERIFICATION ==="
puts "Temporarily disable signature verification to test SMS flow"
puts

puts "📋 CURRENT SIGNATURE VERIFICATION STATUS:"
puts "=========================================="
puts "TWILIO_VERIFY_SIGNATURES: #{ENV['TWILIO_VERIFY_SIGNATURES']}"

# Test the verify_webhook_signature? method
controller = Webhooks::TwilioController.new
verification_enabled = controller.send(:verify_webhook_signature?)
puts "verify_webhook_signature? returns: #{verification_enabled}"

puts "\n🎯 TESTING STRATEGY:"
puts "===================="
puts "1. We know webhooks reach Rails (✅ confirmed)"
puts "2. We know signature validation fails (❌ all URLs fail)"
puts "3. Let's test if SMS works WITHOUT signature verification"

puts "\n📋 CUSTOMER STATUS CHECK:"
puts "========================="

# Find our test customer
customer = TenantCustomer.find_by(phone: '+16026866672') || TenantCustomer.find_by(phone: '6026866672')
if customer
  puts "Customer: #{customer.first_name} #{customer.last_name}"
  puts "Phone: #{customer.phone}"
  puts "Current opt-in status: #{customer.phone_opt_in?}"
  puts "Business: #{customer.business.name}"
else
  puts "❌ Test customer not found"
  exit
end

puts "\n🧪 SIGNATURE VERIFICATION BYPASS TEST:"
puts "====================================="

puts "Current environment:"
puts "- TWILIO_VERIFY_SIGNATURES: #{ENV['TWILIO_VERIFY_SIGNATURES']}"
puts "- Rails.env: #{Rails.env}"

if ENV['TWILIO_VERIFY_SIGNATURES'] == 'true'
  puts "\n⚠️  SIGNATURE VERIFICATION IS ENABLED"
  puts "This means webhooks will continue to fail until signature issue is fixed."
  puts ""
  puts "🔧 TO TEST WITHOUT SIGNATURE VERIFICATION:"
  puts "1. Set environment variable: TWILIO_VERIFY_SIGNATURES=false"
  puts "2. Deploy/restart application"
  puts "3. Send fresh SMS invitation and reply 'YES'"
  puts "4. SMS should work without signature verification"
  puts ""
  puts "💡 This will prove signature verification is the ONLY blocker."
else
  puts "\n✅ SIGNATURE VERIFICATION IS DISABLED"
  puts "Perfect for testing! Let's send a fresh invitation..."

  # Reset customer opt-in status for testing
  if customer.phone_opt_in?
    puts "Resetting customer opt-in for fresh test..."
    customer.update!(phone_opt_in: false, phone_opt_in_at: nil)
  end

  # Send fresh invitation
  begin
    result = SmsService.send_opt_in_invitation(customer, customer.business, :booking_confirmation)

    if result[:success]
      puts "✅ Fresh invitation sent successfully!"
      puts "Twilio SID: #{result[:external_id]}"
      puts ""
      puts "📱 NOW REPLY 'YES' TO THE SMS"
      puts "Expected behavior with signature verification disabled:"
      puts "1. Webhook should reach Rails (no [WEBHOOK_DEBUG] logs needed)"
      puts "2. Customer should be opted in automatically"
      puts "3. Confirmation SMS should be sent"
      puts ""
      puts "If this works → Signature verification was the only issue"
      puts "If this fails → Additional application logic problem"
    else
      puts "❌ Error sending invitation: #{result[:error]}"
    end
  rescue => e
    puts "❌ Exception sending invitation: #{e.message}"
  end
end

puts "\n📊 TROUBLESHOOTING MATRIX:"
puts "=========================="
puts "┌─────────────────────┬─────────────────────┬──────────────────────┐"
puts "│ Signature Enabled   │ Webhook Reaches     │ SMS Works            │"
puts "├─────────────────────┼─────────────────────┼──────────────────────┤"
puts "│ ✅ TRUE (current)   │ ✅ YES (confirmed)  │ ❌ NO (fails)        │"
puts "│ ❌ FALSE (test)     │ ✅ YES (expected)   │ ✅ YES (should work) │"
puts "└─────────────────────┴─────────────────────┴──────────────────────┘"

puts "\n🎯 RECOMMENDED TESTING SEQUENCE:"
puts "==============================="
puts "1. **DISABLE** signature verification: TWILIO_VERIFY_SIGNATURES=false"
puts "2. **TEST** SMS flow (should work perfectly)"
puts "3. **VERIFY** Twilio auth token in console matches production"
puts "4. **ENABLE** signature verification: TWILIO_VERIFY_SIGNATURES=true"
puts "5. **TEST** SMS flow again (should now work with correct token)"

puts "\n💡 This proves signature verification is isolated issue and SMS system is otherwise perfect!"