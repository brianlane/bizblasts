puts "=== Webhook Signature Verification Check ==="

# Check current signature verification settings
puts "Rails environment: #{Rails.env}"
puts "TWILIO_VERIFY_SIGNATURES env var: #{ENV['TWILIO_VERIFY_SIGNATURES'] || 'not set'}"

controller = Webhooks::TwilioController.new
verify_enabled = controller.send(:verify_webhook_signature?)
puts "Signature verification enabled: #{verify_enabled}"

# Check if Twilio auth token is configured
twilio_token_present = ENV['TWILIO_AUTH_TOKEN'].present?
puts "TWILIO_AUTH_TOKEN configured: #{twilio_token_present}"

if Rails.env.production?
  puts "Production environment: signature verification enabled by default"
else
  puts "Non-production environment: signature verification disabled by default"
end

puts
puts "=== Checking Recent Production Activity ==="

# Look for any recent webhook activity in logs or error tracking
# Check if there are failed webhook attempts

recent_sms_attempts = SmsMessage.where('created_at > ?', 1.hour.ago).count
puts "Recent SMS message records: #{recent_sms_attempts}"

puts
puts "=== Signature Verification Status ==="
if verify_enabled && !twilio_token_present
  puts "❌ ISSUE: Signature verification enabled but TWILIO_AUTH_TOKEN missing"
elsif verify_enabled && twilio_token_present
  puts "✅ Signature verification properly configured"
else
  puts "ℹ️  Signature verification disabled"
end

puts
puts "=== Recommendations ==="
if verify_enabled && Rails.env.production?
  puts "Production signature verification is active."
  puts "If webhooks are failing, check:"
  puts "1. TWILIO_AUTH_TOKEN is correctly set"
  puts "2. Webhook URL matches exactly what Twilio is calling"
  puts "3. No proxy/redirect issues"
  puts
  puts "To temporarily disable for testing:"
  puts "Set environment variable: TWILIO_VERIFY_SIGNATURES=false"
else
  puts "Signature verification is disabled - webhooks should process"
end