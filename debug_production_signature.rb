puts "=== Production Signature Verification Debug ==="
puts "This script helps diagnose webhook signature verification issues"
puts

# Check production environment settings
puts "📋 PRODUCTION ENVIRONMENT CHECK:"
puts "  Rails environment: #{Rails.env}"
puts "  Is production?: #{Rails.env.production?}"

# Check signature verification configuration
controller = Webhooks::TwilioController.new
verify_enabled = controller.send(:verify_webhook_signature?)
puts "  Signature verification enabled: #{verify_enabled}"

# Check Twilio credentials
twilio_sid_present = ENV['TWILIO_ACCOUNT_SID'].present?
twilio_token_present = ENV['TWILIO_AUTH_TOKEN'].present?
twilio_phone_present = ENV['TWILIO_PHONE_NUMBER'].present?

puts
puts "📋 TWILIO CONFIGURATION:"
puts "  TWILIO_ACCOUNT_SID: #{twilio_sid_present ? 'Present' : 'MISSING'}"
puts "  TWILIO_AUTH_TOKEN: #{twilio_token_present ? 'Present' : 'MISSING'}"
puts "  TWILIO_PHONE_NUMBER: #{twilio_phone_present ? 'Present' : 'MISSING'}"

if twilio_token_present
  puts "  Token length: #{ENV['TWILIO_AUTH_TOKEN'].length} chars"
  puts "  Token prefix: #{ENV['TWILIO_AUTH_TOKEN'][0..7]}..."
end

puts
puts "📋 WEBHOOK SIGNATURE VERIFICATION STATUS:"

if Rails.env.production? && verify_enabled
  if twilio_token_present
    puts "✅ Production signature verification properly configured"
    puts "   This is SECURE but may cause webhook failures if:"
    puts "   - URL mismatch between Twilio config and Rails routes"
    puts "   - Token mismatch"
    puts "   - Proxy/redirect issues"
  else
    puts "❌ CRITICAL: Signature verification enabled but token missing!"
    puts "   ALL webhooks will fail with 403 errors"
  end
elsif Rails.env.production? && !verify_enabled
  puts "⚠️  Production signature verification DISABLED"
  puts "   Webhooks will process but this is less secure"
else
  puts "ℹ️  Non-production environment with signature verification disabled"
end

puts
puts "📋 RECOMMENDED ACTIONS:"

if Rails.env.production? && verify_enabled && twilio_token_present
  puts "1. Check production logs for webhook signature errors"
  puts "2. Verify webhook URL exactly matches Twilio configuration"
  puts "3. Consider temporarily disabling signature verification for testing:"
  puts "   Set: TWILIO_VERIFY_SIGNATURES=false"
  puts "4. Re-enable after confirming webhook logic works"

elsif Rails.env.production? && verify_enabled && !twilio_token_present
  puts "🚨 URGENT: Set TWILIO_AUTH_TOKEN environment variable"
  puts "   Without this, ALL webhooks will fail!"

elsif Rails.env.production? && !verify_enabled
  puts "1. Webhooks should process successfully"
  puts "2. If still failing, check application logs for errors"
  puts "3. Consider enabling signature verification for security:"
  puts "   Remove: TWILIO_VERIFY_SIGNATURES=false"

else
  puts "1. This appears to be a development/test environment"
  puts "2. Production behavior may differ"
  puts "3. Test in production or staging environment"
end

puts
puts "📋 IMMEDIATE TEST SOLUTION:"
puts "To quickly test if signature verification is the issue:"
puts "1. Temporarily set: TWILIO_VERIFY_SIGNATURES=false"
puts "2. Test SMS opt-in again"
puts "3. If it works, signature verification was the problem"
puts "4. Re-enable signature verification and fix the underlying issue"