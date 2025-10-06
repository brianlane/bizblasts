puts "=== Simple Webhook Processing Debug ==="

# Find the customer we're testing with
customer = TenantCustomer.find_by(phone: '+16026866672')
puts "Customer: #{customer.first_name} #{customer.last_name} (ID: #{customer.id})"
puts "Current opt-in status: #{customer.phone_opt_in?}"
puts

# Test the core webhook processing logic directly
puts "=== Testing Core Webhook Logic ==="

# Get the controller class but don't instantiate it
controller_class = Webhooks::TwilioController

# Mock the exact parameters Twilio sends
webhook_params = {
  'From' => '+16026866672',
  'To' => '+18556128814',
  'Body' => 'YES',
  'MessageSid' => 'SM_test_debug_simple',
  'AccountSid' => ENV['TWILIO_ACCOUNT_SID'] || 'AC_test'
}

puts "Testing with webhook parameters:"
webhook_params.each { |k, v| puts "  #{k}: #{v}" }
puts

# Test customer lookup
phone_number = webhook_params['From']
puts "=== Testing Customer Lookup ==="
puts "Looking up customer by phone: #{phone_number}"
found_customers = TenantCustomer.where(phone: phone_number)
puts "Found #{found_customers.count} customers with this phone number"
found_customers.each do |c|
  puts "  - Customer #{c.id}: #{c.first_name} #{c.last_name}, Business: #{c.business.name}"
end

# Test the SMS message body processing
body = webhook_params['Body'].to_s.strip.upcase
puts "=== Testing Message Body Processing ==="
puts "Raw body: '#{webhook_params['Body']}'"
puts "Processed body: '#{body}'"
puts "Is YES?: #{body == 'YES'}"
puts

# Test if we have recent invitations for this phone
puts "=== Testing Recent Invitations ==="
recent_invitations = SmsOptInInvitation.where(
  phone_number: phone_number
).where('created_at > ?', 7.days.ago)

puts "Recent invitations (last 7 days): #{recent_invitations.count}"
recent_invitations.each do |inv|
  puts "  - #{inv.created_at}: Business #{inv.business.name}, Context: #{inv.context}"
end

# Test creating the SmsMessage record
puts "=== Testing SmsMessage Creation ==="
begin
  sms_message = SmsMessage.create!(
    phone_number: phone_number,
    content: webhook_params['Body'],
    direction: 'inbound',
    status: 'received',
    twilio_message_sid: webhook_params['MessageSid'],
    business: found_customers.first&.business
  )
  puts "✅ SmsMessage created successfully: #{sms_message.id}"
rescue => e
  puts "❌ SmsMessage creation failed: #{e.message}"
end

# Test the opt-in processing
puts "=== Testing Opt-in Processing ==="
if found_customers.any? && body == 'YES'
  customer = found_customers.first
  puts "Processing opt-in for customer #{customer.id}"

  begin
    # This is what the webhook should do
    customer.opt_into_sms!
    customer.reload
    puts "✅ Customer opt-in status after processing: #{customer.phone_opt_in?}"

    # Check for pending notifications
    pending_count = PendingSmsNotification.where(tenant_customer: customer).count
    puts "Pending notifications for this customer: #{pending_count}"

  rescue => e
    puts "❌ Opt-in processing failed: #{e.message}"
  end
else
  puts "❌ Cannot process opt-in - no customers found or body is not YES"
end

puts "=== Debug Complete ==="