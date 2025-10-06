puts "=== SECURE WEBHOOK CONFIGURATION GUIDE ==="
puts "Now that webhooks are working, let's configure them securely"
puts

puts "📋 CURRENT STATUS:"
puts "✅ Webhook URL: https://www.bizblasts.com/webhooks/twilio/inbound"
puts "✅ Signature verification: DISABLED (working but insecure)"
puts "🎯 Goal: Re-enable signature verification with proper configuration"
puts

puts "🔧 STEPS TO SECURE YOUR WEBHOOKS:"
puts "================================="
puts

puts "1. VERIFY TWILIO CREDENTIALS:"
puts "   Check that these environment variables are correctly set:"
puts "   - TWILIO_ACCOUNT_SID: #{ENV['TWILIO_ACCOUNT_SID'].present? ? 'Present' : 'MISSING'}"
puts "   - TWILIO_AUTH_TOKEN: #{ENV['TWILIO_AUTH_TOKEN'].present? ? 'Present' : 'MISSING'}"

if ENV['TWILIO_AUTH_TOKEN'].present?
  puts "   - Token length: #{ENV['TWILIO_AUTH_TOKEN'].length} characters"
  puts "   - Token starts with: #{ENV['TWILIO_AUTH_TOKEN'][0..7]}..."
end

puts
puts "2. TEST SIGNATURE VERIFICATION:"
puts "   Before re-enabling, test with a single webhook call:"
puts "   a) Temporarily set: TWILIO_VERIFY_SIGNATURES=true"
puts "   b) Send yourself a test SMS invitation"
puts "   c) Reply 'YES' and check if it processes"
puts "   d) Check production logs for signature validation errors"
puts

puts "3. COMMON SIGNATURE ISSUES & SOLUTIONS:"
puts "   If signature verification fails after re-enabling:"
puts
puts "   🔍 Issue: 'Invalid signature' errors"
puts "   💡 Solution: Verify webhook URL exactly matches Twilio config"
puts "      - Twilio calls: https://www.bizblasts.com/webhooks/twilio/inbound"
puts "      - Rails expects: same URL (no redirects)"
puts
puts "   🔍 Issue: Token mismatch"
puts "   💡 Solution: Verify TWILIO_AUTH_TOKEN matches Twilio console"
puts "      - Go to: https://console.twilio.com/us1/develop/runtime/api-keys"
puts "      - Check 'Auth Token' matches your environment variable"
puts
puts "   🔍 Issue: Proxy/load balancer interference"
puts "   💡 Solution: Check headers in production logs"
puts "      - Look for X-Forwarded-Host, X-Original-Host headers"
puts "      - Webhook signature validation is sensitive to URL changes"
puts

puts "4. GRADUAL RE-ENABLEMENT STRATEGY:"
puts "   a) Set TWILIO_VERIFY_SIGNATURES=true"
puts "   b) Deploy and test immediately"
puts "   c) If it works: ✅ You're secure!"
puts "   d) If it fails: Set back to false, debug, repeat"
puts

puts "5. MONITORING & VALIDATION:"
puts "   After re-enabling signature verification:"
puts "   - Test SMS opt-in flow end-to-end"
puts "   - Monitor production logs for webhook errors"
puts "   - Verify no 403 'Invalid signature' errors"
puts "   - Confirm customers can successfully opt in/out"
puts

puts "📱 IMMEDIATE TEST PLAN:"
puts "======================"
puts "Once you re-enable signature verification:"
puts "1. Send SMS invitation to your phone"
puts "2. Reply 'YES'"
puts "3. Expect: Confirmation SMS within 15 seconds"
puts "4. If no confirmation: Check logs, investigate signature validation"
puts

puts "🎯 FINAL GOAL:"
puts "=============="
puts "Environment variables in production:"
puts "  TWILIO_VERIFY_SIGNATURES=true    (secure)"
puts "  TWILIO_ACCOUNT_SID=AC...          (your account)"
puts "  TWILIO_AUTH_TOKEN=your_token      (32 char token)"
puts
puts "When this is working, you'll have:"
puts "✅ Secure webhook signature validation"
puts "✅ Fully functional SMS opt-in/opt-out"
puts "✅ Production-ready SMS system"