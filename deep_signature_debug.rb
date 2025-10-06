puts "=== DEEP SIGNATURE VALIDATION DEBUGGING ==="
puts "Investigating fundamental signature validation failure"
puts

# Step-by-step signature validation debugging
puts "📋 DETAILED SIGNATURE GENERATION TEST:"
puts "====================================="

auth_token = ENV['TWILIO_AUTH_TOKEN']
test_url = "https://www.bizblasts.com/webhooks/twilio/inbound"
test_body = "From=%2B16026866672&To=%2B18556128814&Body=YES&MessageSid=SM123test"

puts "Auth token: #{auth_token[0..7]}...#{auth_token[-8..-1]}"
puts "Test URL: #{test_url}"
puts "Test body: #{test_body}"

# Manual signature generation (exactly how Twilio does it)
puts "\n📋 MANUAL SIGNATURE GENERATION:"
puts "==============================="

require 'base64'
require 'openssl'

begin
  # Step 1: Concatenate URL and body
  data_to_sign = test_url + test_body
  puts "Data to sign: #{data_to_sign}"
  puts "Data length: #{data_to_sign.length}"

  # Step 2: Create HMAC-SHA1 digest
  digest = OpenSSL::Digest.new('sha1')
  puts "Digest algorithm: #{digest.name}"

  # Step 3: Generate HMAC
  hmac_result = OpenSSL::HMAC.digest(digest, auth_token, data_to_sign)
  puts "HMAC result length: #{hmac_result.length} bytes"
  puts "HMAC result (hex): #{hmac_result.unpack1('H*')}"

  # Step 4: Base64 encode
  signature = Base64.encode64(hmac_result).strip
  puts "Base64 signature: #{signature}"
  puts "Signature length: #{signature.length}"

  # Step 5: Test with Twilio SDK
  puts "\n📋 TWILIO SDK VALIDATION TEST:"
  puts "=============================="

  require 'twilio-ruby'
  validator = Twilio::Security::RequestValidator.new(auth_token)
  puts "Validator created with token: #{auth_token[0..7]}...#{auth_token[-8..-1]}"

  # Test our manually generated signature
  manual_result = validator.validate(test_url, test_body, signature)
  puts "Manual signature validates: #{manual_result}"

  # Try with different encoding
  signature_no_strip = Base64.encode64(hmac_result)
  no_strip_result = validator.validate(test_url, test_body, signature_no_strip)
  puts "Signature without strip validates: #{no_strip_result}"

  # Try with strict encoding
  signature_strict = Base64.strict_encode64(hmac_result)
  strict_result = validator.validate(test_url, test_body, signature_strict)
  puts "Strict Base64 signature validates: #{strict_result}"

  puts "\n📋 TWILIO SDK VERSION INFO:"
  puts "============================"
  puts "Twilio gem version: #{Twilio::VERSION}" if defined?(Twilio::VERSION)

  # Check if we can find the actual Twilio validation method
  puts "\n📋 INSPECTING TWILIO VALIDATOR:"
  puts "==============================="

  validator_methods = validator.methods.grep(/validate/)
  puts "Validator methods: #{validator_methods}"

  # Try to understand what the validator is actually doing
  puts "\n📋 DEBUGGING VALIDATOR INTERNALS:"
  puts "================================="

  # Let's see if we can manually replicate what the validator does
  # This is based on Twilio's documented algorithm
  def manual_twilio_validation(url, body, signature, auth_token)
    require 'base64'
    require 'openssl'

    data = url + body
    digest = OpenSSL::Digest.new('sha1')
    computed_signature = Base64.encode64(OpenSSL::HMAC.digest(digest, auth_token, data)).strip

    # Secure comparison
    return false unless signature && computed_signature
    return false unless signature.length == computed_signature.length

    # Constant time comparison
    result = 0
    signature.bytes.zip(computed_signature.bytes) { |a, b| result |= a ^ b }
    result == 0
  end

  manual_validation = manual_twilio_validation(test_url, test_body, signature, auth_token)
  puts "Manual Twilio algorithm validates: #{manual_validation}"

  puts "\n📋 SIGNATURE COMPARISON:"
  puts "======================="

  # Let's see what signature the validator expects vs what we generated
  expected_data = test_url + test_body
  expected_hmac = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha1'), auth_token, expected_data)
  expected_signature = Base64.encode64(expected_hmac).strip

  puts "Our signature:      #{signature}"
  puts "Expected signature: #{expected_signature}"
  puts "Signatures match:   #{signature == expected_signature}"

rescue => e
  puts "❌ Error in signature generation: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join(', ')}"
end

puts "\n📋 ENVIRONMENT DEBUGGING:"
puts "========================="
puts "Ruby version: #{RUBY_VERSION}"
puts "Rails version: #{Rails::VERSION::STRING}"

# Check OpenSSL version
puts "OpenSSL version: #{OpenSSL::OPENSSL_VERSION}"

puts "\n💡 ANALYSIS:"
puts "============"
puts "If manual_twilio_validation returns TRUE but validator.validate returns FALSE:"
puts "→ Issue with Twilio Ruby SDK implementation"
puts "→ Possible gem version incompatibility"
puts "→ May need to use manual validation or update gem"
puts ""
puts "If ALL validation methods return FALSE:"
puts "→ Fundamental issue with token or algorithm"
puts "→ Need to verify auth token in Twilio console"
puts "→ Possible encoding/character set issue"

puts "\n🎯 NEXT STEPS:"
puts "=============="
puts "1. If manual validation works → Use manual implementation"
puts "2. If all fail → Verify Twilio auth token in console"
puts "3. Test with signature verification disabled to prove SMS system works"