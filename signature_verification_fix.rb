puts "=== SIGNATURE VERIFICATION FIX STRATEGY ==="
puts "Based on analysis, here's the most likely fix needed"
puts

puts "🎯 MOST LIKELY ISSUE: URL MISMATCH"
puts "=================================="
puts "Twilio generates signature using: https://www.bizblasts.com/webhooks/twilio/inbound"
puts "But Rails might be reconstructing:  https://something-else/webhooks/twilio/inbound"
puts

puts "💡 QUICK FIX SOLUTION:"
puts "======================"
puts "Add this environment variable to force URL reconstruction:"
puts "  TWILIO_WEBHOOK_DOMAIN=www.bizblasts.com"
puts

puts "This will make the reconstruct_original_url method use the correct domain."
puts

puts "📋 TESTING STEPS:"
puts "================="
puts "1. Add environment variable: TWILIO_WEBHOOK_DOMAIN=www.bizblasts.com"
puts "2. Set: TWILIO_VERIFY_SIGNATURES=true"
puts "3. Deploy to production"
puts "4. Test SMS opt-in with a reply"
puts "5. If it works: ✅ Problem solved!"
puts "6. If not: Continue with detailed logging approach"
puts

puts "🔧 ALTERNATIVE FIXES (if first doesn't work):"
puts "============================================="
puts
puts "FIX 1: Hardcode the URL reconstruction"
puts "---------------------------------------"
puts "In reconstruct_original_url method, add at the top:"
puts '  return "https://www.bizblasts.com/webhooks/twilio/inbound" if Rails.env.production?'
puts

puts "FIX 2: Update Twilio webhook URL to match what Rails receives"
puts "-------------------------------------------------------------"
puts "Check production logs to see what URL Rails actually receives,"
puts "then update Twilio console to use that exact URL."
puts

puts "FIX 3: Disable complex URL reconstruction"
puts "------------------------------------------"
puts "Simplify reconstruct_original_url to just return request.original_url"
puts "and ensure Twilio calls the exact same URL."
puts

puts "🚀 RECOMMENDED APPROACH:"
puts "========================"
puts "Start with the environment variable fix (simplest):"
puts "  TWILIO_WEBHOOK_DOMAIN=www.bizblasts.com"
puts "  TWILIO_VERIFY_SIGNATURES=true"
puts
puts "This should resolve the signature verification immediately."

# Let's also test what the current logic would produce
puts
puts "🧪 TESTING CURRENT URL RECONSTRUCTION LOGIC:"
puts "============================================="

# Create a mock controller to test the logic
controller = Webhooks::TwilioController.new

# Mock different scenarios
class MockRequest
  attr_accessor :host, :original_url, :headers_hash

  def initialize(host, original_url, headers = {})
    @host = host
    @original_url = original_url
    @headers_hash = headers
  end

  def headers
    @headers_hash
  end
end

# Test scenarios
scenarios = [
  {
    name: "Direct www call",
    host: "www.bizblasts.com",
    url: "https://www.bizblasts.com/webhooks/twilio/inbound",
    headers: {}
  },
  {
    name: "Load balancer scenario",
    host: "internal-host",
    url: "https://internal-host/webhooks/twilio/inbound",
    headers: { "X-Forwarded-Host" => "www.bizblasts.com" }
  },
  {
    name: "With TWILIO_WEBHOOK_DOMAIN set",
    host: "www.bizblasts.com",
    url: "https://www.bizblasts.com/webhooks/twilio/inbound",
    headers: {},
    env_domain: "www.bizblasts.com"
  }
]

scenarios.each_with_index do |scenario, index|
  puts "Scenario #{index + 1}: #{scenario[:name]}"

  # Set environment variable if specified
  if scenario[:env_domain]
    ENV['TWILIO_WEBHOOK_DOMAIN'] = scenario[:env_domain]
  else
    ENV.delete('TWILIO_WEBHOOK_DOMAIN')
  end

  # Mock the request
  mock_request = MockRequest.new(scenario[:host], scenario[:url], scenario[:headers])
  controller.instance_variable_set(:@request, mock_request)

  # Test reconstruction
  begin
    reconstructed = controller.send(:reconstruct_original_url)
    puts "  Input URL: #{scenario[:url]}"
    puts "  Output URL: #{reconstructed}"
    puts "  Match: #{reconstructed == 'https://www.bizblasts.com/webhooks/twilio/inbound' ? '✅' : '❌'}"
  rescue => e
    puts "  Error: #{e.message}"
  end
  puts
end

# Clean up
ENV.delete('TWILIO_WEBHOOK_DOMAIN')

puts "💡 CONCLUSION:"
puts "=============="
puts "The environment variable TWILIO_WEBHOOK_DOMAIN=www.bizblasts.com"
puts "should force the correct URL reconstruction for signature verification."