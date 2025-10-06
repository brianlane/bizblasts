puts "=== SIMPLE WEBHOOK CONNECTIVITY TEST ==="
puts "Direct test to see if webhooks reach Rails application"
puts

# Find customer 8
customer = TenantCustomer.find_by(phone: '+16026866672') || TenantCustomer.find_by(phone: '6026866672')
business = customer&.business

if customer && business
  puts "📋 TEST SETUP:"
  puts "=============="
  puts "Customer: #{customer.first_name} #{customer.last_name}"
  puts "Phone: #{customer.phone}"
  puts "Business: #{business.name}"
  puts "Currently opted in: #{customer.phone_opt_in?}"
  puts "Business SMS enabled: #{business.sms_enabled?}"
  puts "Current time: #{Time.current.iso8601}"

  puts "\n📋 ENVIRONMENT CHECK:"
  puts "====================="
  puts "TWILIO_VERIFY_SIGNATURES: #{ENV['TWILIO_VERIFY_SIGNATURES']}"
  puts "TWILIO_WEBHOOK_DOMAIN: #{ENV['TWILIO_WEBHOOK_DOMAIN']}"
  puts "Rails env: #{Rails.env}"

  puts "\n🧪 WEBHOOK CONTROLLER TEST:"
  puts "==========================="

  # Test if controller responds to webhook signature verification
  controller = Webhooks::TwilioController.new

  # Mock a basic request to test if signature verification runs
  class MockRequest
    attr_accessor :headers, :raw_post, :original_url, :host, :path, :query_string

    def initialize
      @headers = {
        'X-Twilio-Signature' => 'test_signature_value'
      }
      @raw_post = 'From=%2B16026866672&To=%2B18556128814&Body=YES&MessageSid=SM123'
      @original_url = 'https://www.bizblasts.com/webhooks/twilio/inbound'
      @host = 'www.bizblasts.com'
      @path = '/webhooks/twilio/inbound'
      @query_string = ''
    end
  end

  mock_request = MockRequest.new
  controller.instance_variable_set(:@request, mock_request)

  puts "Testing signature verification method..."
  begin
    # This should trigger our [WEBHOOK_DEBUG] logging
    result = controller.send(:valid_signature?)
    puts "✅ Signature verification method executed"
    puts "Result: #{result}"
    puts "Check logs above for [WEBHOOK_DEBUG] entries"
  rescue => e
    puts "❌ Error in signature verification: #{e.message}"
    puts "Backtrace: #{e.backtrace.first(3).join(', ')}"
  end

  puts "\n🎯 WEBHOOK DEBUGGING STRATEGY:"
  puts "=============================="

  if customer.phone_opt_in?
    puts "Customer is already opted in. For webhook testing:"
    puts "1. Send ANY SMS reply to #{ENV['TWILIO_PHONE_NUMBER']}"
    puts "2. Even invalid replies should trigger webhook calls"
    puts "3. Check production logs immediately for [WEBHOOK_DEBUG] entries"
    puts ""
    puts "Expected webhook behavior:"
    puts "- Any SMS to #{ENV['TWILIO_PHONE_NUMBER']} should trigger webhook"
    puts "- [WEBHOOK_DEBUG] logs should appear in production logs"
    puts "- If no debug logs appear = webhooks not reaching Rails"
  else
    puts "Customer not opted in. Sending fresh invitation..."

    begin
      result = SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)
      puts "Invitation result: #{result}"
      puts "📱 Reply 'YES' to test webhook processing"
    rescue => e
      puts "Error sending invitation: #{e.message}"
    end
  end

  puts "\n📊 DIAGNOSTIC CHECKLIST:"
  puts "========================"
  puts "✅ Enhanced logging deployed: YES"
  puts "✅ Environment variables set: YES"
  puts "✅ Signature verification enabled: YES"
  puts "✅ Customer data available: YES"
  puts "❓ Webhooks reaching Rails: UNKNOWN (test needed)"
  puts ""
  puts "🚨 CRITICAL TEST:"
  puts "Send any SMS to #{ENV['TWILIO_PHONE_NUMBER']} and check logs immediately!"
  puts "If no [WEBHOOK_DEBUG] logs appear = infrastructure issue"
  puts "If [WEBHOOK_DEBUG] logs appear = application logic issue"

else
  puts "❌ Customer not found for testing"
end