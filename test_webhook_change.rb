puts "=== Comprehensive Webhook URL Change Test ==="
puts "This script will help you test the Twilio webhook URL change"
puts

# Step 1: Pre-change verification
puts "📋 STEP 1: PRE-CHANGE VERIFICATION"
puts "Current Twilio configuration should be: https://bizblasts.com/webhooks/twilio/inbound"
puts

require 'net/http'
require 'uri'

def test_webhook_url(url, test_name)
  puts "🔄 Testing #{test_name}: #{url}"

  uri = URI(url)
  webhook_params = {
    'From' => '+16026866672',
    'To' => '+18556128814',
    'Body' => 'TEST_WEBHOOK',
    'MessageSid' => "SM_test_#{Time.now.to_i}",
    'AccountSid' => ENV['TWILIO_ACCOUNT_SID'] || 'AC_test'
  }

  begin
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(webhook_params)
    request['User-Agent'] = 'TwilioProxy/1.1'

    response = http.request(request)

    puts "  Status: #{response.code} #{response.message}"

    case response.code.to_i
    when 200
      puts "  ✅ SUCCESS: Webhook processed correctly"
      puts "  Response: #{response.body[0..100]}..."
    when 307
      puts "  ⚠️  REDIRECT: #{response['location']}"
      puts "  ❌ This means Twilio won't process the webhook"
    when 403
      puts "  ⚠️  FORBIDDEN: #{response.body}"
      puts "  ℹ️  This means webhook reached processing but signature failed (expected in test)"
    else
      puts "  ❌ UNEXPECTED: #{response.body[0..100]}..."
    end

    return response.code.to_i

  rescue => e
    puts "  ❌ ERROR: #{e.message}"
    return nil
  end
end

# Test current configuration (should redirect)
puts "Testing current configuration (should show redirect):"
old_status = test_webhook_url("https://bizblasts.com/webhooks/twilio/inbound", "Current URL (bizblasts.com)")
puts

# Test target configuration (should work)
puts "Testing target configuration (should work after change):"
new_status = test_webhook_url("https://www.bizblasts.com/webhooks/twilio/inbound", "Target URL (www.bizblasts.com)")
puts

# Verification
puts "📊 PRE-CHANGE VERIFICATION RESULTS:"
if old_status == 307
  puts "✅ Confirmed: Current URL redirects (explains webhook failure)"
else
  puts "❓ Unexpected: Current URL status = #{old_status}"
end

if new_status == 403
  puts "✅ Confirmed: Target URL reaches webhook processing"
elsif new_status == 200
  puts "✅ Perfect: Target URL processes webhooks successfully"
else
  puts "❓ Unexpected: Target URL status = #{new_status}"
end

puts
puts "🔧 STEP 2: MAKE THE CHANGE"
puts "Now update your Twilio Console configuration:"
puts "1. Go to: https://console.twilio.com/us1/develop/phone-numbers/manage/incoming"
puts "2. Click on phone number: (855) 612-8814"
puts "3. Update webhook URL from:"
puts "   OLD: https://bizblasts.com/webhooks/twilio/inbound"
puts "   NEW: https://www.bizblasts.com/webhooks/twilio/inbound"
puts "4. Save the configuration"
puts
puts "⏳ After making the change, run: bundle exec rails runner test_webhook_verification.rb"