puts "=== Testing Webhook HTTP Endpoint ==="

require 'net/http'
require 'uri'

# Test the webhook endpoint with an HTTP request
webhook_url = "https://bizblasts.com/webhooks/twilio/inbound"
uri = URI(webhook_url)

# Create the exact parameters Twilio would send
webhook_params = {
  'From' => '+16026866672',
  'To' => '+18556128814',
  'Body' => 'YES',
  'MessageSid' => 'SM_test_http_request',
  'AccountSid' => ENV['TWILIO_ACCOUNT_SID'] || 'AC_test'
}

puts "Testing webhook endpoint: #{webhook_url}"
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

  puts "🔄 Sending HTTP POST request to webhook..."

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

puts "\n=== Check Customer Status After HTTP Test ==="
customer = TenantCustomer.find_by(phone: '+16026866672')
if customer
  customer.reload
  puts "Customer opted in: #{customer.phone_opt_in?}"
  puts "Customer opt-in timestamp: #{customer.phone_opt_in_at}"
else
  puts "Customer not found"
end

# Check for new SMS messages
recent_sms = SmsMessage.where('created_at > ?', 5.minutes.ago).count
puts "Recent SMS messages (last 5 minutes): #{recent_sms}"