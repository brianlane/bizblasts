puts "=== Testing Webhook with WWW URL ==="

require 'net/http'
require 'uri'

# Test the webhook endpoint with WWW prefix (where the redirect goes)
webhook_url = "https://www.bizblasts.com/webhooks/twilio/inbound"
uri = URI(webhook_url)

# Create the exact parameters Twilio would send
webhook_params = {
  'From' => '+16026866672',
  'To' => '+18556128814',
  'Body' => 'TEST',
  'MessageSid' => 'SM_test_www_request',
  'AccountSid' => ENV['TWILIO_ACCOUNT_SID'] || 'AC_test'
}

puts "Testing webhook endpoint with WWW: #{webhook_url}"
puts "Parameters:"
webhook_params.each { |k, v| puts "  #{k}: #{v}" }
puts

begin
  # Create HTTP client
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  # Create POST request
  request = Net::HTTP::Post.new(uri.request_uri)
  request.set_form_data(webhook_params)

  # Add User-Agent to simulate Twilio
  request['User-Agent'] = 'TwilioProxy/1.1'
  request['Content-Type'] = 'application/x-www-form-urlencoded'

  puts "🔄 Sending HTTP POST request to WWW webhook..."

  # Send request with timeout
  response = http.request(request)

  puts "✅ Response received!"
  puts "Status: #{response.code} #{response.message}"
  puts "Headers:"
  response.each_header { |key, value| puts "  #{key}: #{value}" }
  puts "Body: #{response.body}"

rescue => e
  puts "❌ HTTP request failed:"
  puts "  Error: #{e.message}"
  puts "  Class: #{e.class.name}"
end

puts "\n=== Check for New SMS Messages ==="
# Check for the TEST message we just sent
recent_sms = SmsMessage.where('created_at > ?', 2.minutes.ago)
puts "Recent SMS messages (last 2 minutes): #{recent_sms.count}"
recent_sms.each do |sms|
  puts "  - #{sms.created_at}: #{sms.content} (Phone: #{sms.phone_number})"
end