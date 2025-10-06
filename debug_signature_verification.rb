puts "=== SIGNATURE VERIFICATION DEBUG ==="
puts "Testing each component of Twilio signature verification"
puts

# Check Twilio configuration
puts "📋 TWILIO CONFIGURATION:"
puts "  TWILIO_ACCOUNT_SID: #{ENV['TWILIO_ACCOUNT_SID']&.present? ? 'Present' : 'MISSING'}"
puts "  TWILIO_AUTH_TOKEN: #{ENV['TWILIO_AUTH_TOKEN']&.present? ? 'Present' : 'MISSING'}"

if ENV['TWILIO_AUTH_TOKEN']&.present?
  puts "  Token length: #{ENV['TWILIO_AUTH_TOKEN'].length}"
  puts "  Token preview: #{ENV['TWILIO_AUTH_TOKEN'][0..7]}..."

  # Test if constant is properly defined
  puts "  Constant TWILIO_AUTH_TOKEN defined: #{defined?(TWILIO_AUTH_TOKEN).present?}"
  if defined?(TWILIO_AUTH_TOKEN)
    puts "  Constant matches ENV: #{TWILIO_AUTH_TOKEN == ENV['TWILIO_AUTH_TOKEN']}"
  end
end

puts

# Test signature verification components
puts "🔧 TESTING SIGNATURE VERIFICATION COMPONENTS:"
puts

# 1. Test Twilio SDK RequestValidator
puts "1. Testing Twilio::Security::RequestValidator:"
begin
  if defined?(TWILIO_AUTH_TOKEN)
    validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
    puts "   ✅ RequestValidator created successfully"
  else
    puts "   ❌ TWILIO_AUTH_TOKEN constant not defined"
  end
rescue => e
  puts "   ❌ Error creating RequestValidator: #{e.message}"
end

puts

# 2. Test a sample signature validation
puts "2. Testing sample signature validation:"
sample_url = "https://www.bizblasts.com/webhooks/twilio/inbound"
sample_body = "From=%2B16026866672&To=%2B18556128814&Body=YES&MessageSid=SM123"

# Generate a test signature using Twilio's method
begin
  require 'base64'
  require 'openssl'

  if defined?(TWILIO_AUTH_TOKEN)
    # This is how Twilio generates signatures
    data_to_sign = sample_url + sample_body
    digest = OpenSSL::Digest.new('sha1')
    test_signature = Base64.encode64(OpenSSL::HMAC.digest(digest, TWILIO_AUTH_TOKEN, data_to_sign)).strip

    puts "   Test URL: #{sample_url}"
    puts "   Test body: #{sample_body}"
    puts "   Generated signature: #{test_signature[0..20]}..."

    # Test validation
    validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
    is_valid = validator.validate(sample_url, sample_body, test_signature)
    puts "   Validation result: #{is_valid ? '✅ VALID' : '❌ INVALID'}"
  else
    puts "   ❌ Cannot test - TWILIO_AUTH_TOKEN not available"
  end
rescue => e
  puts "   ❌ Error in signature test: #{e.message}"
end

puts

# 3. Test URL reconstruction logic
puts "3. Testing URL reconstruction scenarios:"

# Mock different request scenarios
test_scenarios = [
  {
    name: "Direct call to www.bizblasts.com",
    host: "www.bizblasts.com",
    original_url: "https://www.bizblasts.com/webhooks/twilio/inbound",
    headers: {}
  },
  {
    name: "Call via proxy with X-Forwarded-Host",
    host: "internal-server",
    original_url: "https://internal-server/webhooks/twilio/inbound",
    headers: { "X-Forwarded-Host" => "www.bizblasts.com" }
  },
  {
    name: "Call with redirect headers",
    host: "www.bizblasts.com",
    original_url: "https://www.bizblasts.com/webhooks/twilio/inbound",
    headers: { "X-Original-Host" => "bizblasts.com" }
  }
]

test_scenarios.each_with_index do |scenario, index|
  puts "   Scenario #{index + 1}: #{scenario[:name]}"
  puts "     Host: #{scenario[:host]}"
  puts "     Original URL: #{scenario[:original_url]}"
  puts "     Headers: #{scenario[:headers]}"

  # Simulate the reconstruct_original_url logic
  current_url = scenario[:original_url]

  # Check X-Forwarded-Host
  forwarded_host = scenario[:headers]["X-Forwarded-Host"]
  if forwarded_host.present? && forwarded_host != scenario[:host]
    reconstructed_url = current_url.gsub(scenario[:host], forwarded_host)
    puts "     ➜ Reconstructed (X-Forwarded-Host): #{reconstructed_url}"
  else
    puts "     ➜ No reconstruction needed: #{current_url}"
  end
  puts
end

puts

# 4. Test webhook controller logic
puts "4. Testing webhook controller methods:"

controller = Webhooks::TwilioController.new

# Test verify_webhook_signature? method
verify_enabled = controller.send(:verify_webhook_signature?)
puts "   verify_webhook_signature?: #{verify_enabled}"

puts "   Rails.env.production?: #{Rails.env.production?}"
puts "   ENV['TWILIO_VERIFY_SIGNATURES']: #{ENV['TWILIO_VERIFY_SIGNATURES'] || 'not set'}"

puts

# 5. Identify potential issues
puts "🔍 POTENTIAL SIGNATURE VERIFICATION ISSUES:"
puts

issues_found = []

if !defined?(TWILIO_AUTH_TOKEN)
  issues_found << "TWILIO_AUTH_TOKEN constant not defined"
end

if ENV['TWILIO_AUTH_TOKEN'].blank?
  issues_found << "TWILIO_AUTH_TOKEN environment variable missing"
end

if ENV['TWILIO_AUTH_TOKEN']&.length != 32
  issues_found << "TWILIO_AUTH_TOKEN length incorrect (should be 32 chars)"
end

if issues_found.any?
  puts "❌ CRITICAL ISSUES FOUND:"
  issues_found.each { |issue| puts "   - #{issue}" }
else
  puts "✅ Basic configuration looks correct"
  puts
  puts "🎯 LIKELY ISSUES IN PRODUCTION:"
  puts "   1. URL mismatch - Twilio calls one URL, Rails reconstructs different URL"
  puts "   2. Request body modification by proxy/middleware"
  puts "   3. Missing or incorrect X-Twilio-Signature header"
  puts "   4. URL reconstruction logic incorrectly modifying the URL"
  puts
  puts "💡 DEBUGGING STRATEGY:"
  puts "   1. Enable detailed webhook logging in production"
  puts "   2. Log the exact URL and body used for signature verification"
  puts "   3. Compare with what Twilio expects"
  puts "   4. Check for proxy/load balancer interference"
end

puts
puts "📋 NEXT STEPS:"
puts "1. Enable signature verification logging in production"
puts "2. Test with a single SMS and examine logs"
puts "3. Identify URL/body/signature mismatches"
puts "4. Fix the specific issue found"