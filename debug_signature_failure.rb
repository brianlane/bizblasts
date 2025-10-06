puts "=== SIGNATURE VALIDATION FAILURE DEBUGGING ==="
puts "Investigating why signature validation fails despite correct URLs"
puts

# 1. Check TWILIO_AUTH_TOKEN configuration
puts "📋 TWILIO AUTH TOKEN ANALYSIS:"
puts "=============================="

auth_token = ENV['TWILIO_AUTH_TOKEN']
if auth_token.present?
  puts "✅ TWILIO_AUTH_TOKEN present"
  puts "Token length: #{auth_token.length} characters"
  puts "Token format: #{auth_token.match?(/^[a-f0-9]{32}$/) ? 'Valid hex format' : 'Invalid format'}"
  puts "Token starts with: #{auth_token[0..7]}..."
  puts "Token ends with: ...#{auth_token[-8..-1]}"
else
  puts "❌ TWILIO_AUTH_TOKEN missing!"
  exit
end

puts "\n📋 CONSTANT VERIFICATION:"
puts "========================="
if defined?(TWILIO_AUTH_TOKEN)
  puts "✅ TWILIO_AUTH_TOKEN constant defined"
  puts "Constant matches ENV: #{TWILIO_AUTH_TOKEN == ENV['TWILIO_AUTH_TOKEN']}"
  puts "Constant length: #{TWILIO_AUTH_TOKEN.length}"
else
  puts "❌ TWILIO_AUTH_TOKEN constant not defined"
end

puts "\n📋 RECENT WEBHOOK LOGS ANALYSIS:"
puts "==============================="
puts "From your logs, we know:"
puts "✅ Webhooks reach Rails (debug logs appear)"
puts "✅ Signature present (not nil)"
puts "✅ URLs match exactly (original = reconstructed)"
puts "❌ Signature validation fails (returns false)"
puts "❌ ALL URL variations fail (indicates token/body issue)"

puts "\n🔍 SIGNATURE VALIDATION DEEP DIVE:"
puts "=================================="

# Create a test signature validation to understand the failure
puts "Testing signature validation components..."

begin
  # We'll simulate what we saw in the logs
  test_url = "https://www.bizblasts.com/webhooks/twilio/inbound"

  # Try to create the Twilio validator
  require 'twilio-ruby'
  validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
  puts "✅ Twilio RequestValidator created successfully"

  # Test with sample data to see if validator works at all
  sample_body = "From=%2B16026866672&To=%2B18556128814&Body=YES&MessageSid=SM123test"

  # Generate what the signature SHOULD be for this data
  require 'base64'
  require 'openssl'

  data_to_sign = test_url + sample_body
  digest = OpenSSL::Digest.new('sha1')
  expected_signature = Base64.encode64(OpenSSL::HMAC.digest(digest, TWILIO_AUTH_TOKEN, data_to_sign)).strip

  puts "✅ Generated test signature: #{expected_signature[0..20]}..."

  # Test validation with our generated signature
  validation_result = validator.validate(test_url, sample_body, expected_signature)
  puts "✅ Self-generated signature validates: #{validation_result}"

  if validation_result
    puts "✅ Twilio SDK and auth token are working correctly"
    puts "❌ Issue must be with the actual webhook data (URL, body, or signature)"
  else
    puts "❌ Even self-generated signature fails - token issue!"
  end

rescue => e
  puts "❌ Error in signature validation test: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join(', ')}"
end

puts "\n💡 DIAGNOSIS & NEXT STEPS:"
puts "=========================="

puts "\n🎯 MOST LIKELY CAUSES:"
puts "1. **TWILIO_AUTH_TOKEN MISMATCH**"
puts "   → Production env token ≠ Twilio console auth token"
puts "   → Check Twilio console → Account → API Keys & Tokens"
puts "   → Verify the 'Auth Token' matches production TWILIO_AUTH_TOKEN"

puts "\n2. **REQUEST BODY MODIFICATION**"
puts "   → Middleware/proxy modifying POST body between Twilio and Rails"
puts "   → URL encoding changes, parameter order, etc."
puts "   → Common with load balancers, CDNs, security proxies"

puts "\n3. **WEBHOOK CONFIGURATION MISMATCH**"
puts "   → Twilio webhook URL configured differently than expected"
puts "   → Query parameters, trailing slashes, etc."

puts "\n🔧 IMMEDIATE ACTIONS:"
puts "===================="

puts "\n**STEP 1: Verify Twilio Auth Token**"
puts "1. Go to: https://console.twilio.com/us1/account/keys-credentials/auth-tokens"
puts "2. Click 'Show' on the Auth Token"
puts "3. Compare with your production TWILIO_AUTH_TOKEN"
puts "4. If they don't match → Update production environment variable"

puts "\n**STEP 2: Temporarily Disable Signature Verification**"
puts "1. Set: TWILIO_VERIFY_SIGNATURES=false"
puts "2. Test SMS opt-in flow (should work without signature verification)"
puts "3. If it works → Confirms signature is the only issue"
puts "4. Re-enable after fixing token"

puts "\n**STEP 3: Enhanced Request Logging**"
puts "1. Add temporary logging to capture actual request body"
puts "2. Compare with what Twilio expects for signature generation"
puts "3. Identify any modifications by middleware"

puts "\n🚨 CRITICAL: If self-generated signature test above FAILED:"
puts "→ Definitely a TWILIO_AUTH_TOKEN mismatch"
puts "→ Update production auth token immediately"
puts "→ This is the #1 most likely cause"

puts "\nStatus: Ready for token verification and fix! 🎯"