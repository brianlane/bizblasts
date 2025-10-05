#!/usr/bin/env ruby
# End-to-end webhook flow test

puts "=== End-to-End Webhook Flow Test ==="
puts "This test simulates a complete SMS opt-in response flow"
puts

# Step 1: Create a customer who is NOT opted in initially
business = Business.find_by(id: 1) || Business.create!(
  name: 'Webhook Test Business',
  tier: 'premium',
  hostname: 'webhooktest',
  host_type: 'subdomain',
  sms_enabled: true,
  industry: 'consulting',
  phone: '555-123-4567',
  email: 'test@example.com',
  address: '123 Test St',
  city: 'Test',
  state: 'CA',
  zip: '90210',
  description: 'Webhook test business'
)

# Create customer not opted in (use timestamp for unique email)
timestamp = Time.current.to_i
customer = TenantCustomer.create!(
  business: business,
  first_name: 'Test',
  last_name: 'Customer',
  email: "test-webhook-#{timestamp}@example.com",
  phone: '+15551234567',
  phone_opt_in: false,  # Start NOT opted in
  phone_opt_in_at: nil
)

puts "Step 1: Created test customer"
puts "  Customer ID: #{customer.id}"
puts "  Phone: #{customer.phone}"
puts "  Initially opted in: #{customer.phone_opt_in?}"
puts "  Business: #{business.name}"
puts

# Step 2: Create some pending notifications to test replay
service = Service.create!(
  name: "Test Service #{timestamp}",
  business: business,
  duration: 60,
  price: 100
)

# Create a staff member for the booking
staff_member = User.create!(
  first_name: 'Test',
  last_name: 'Staff',
  email: "staff-#{timestamp}@example.com",
  password: 'password123',
  role: 'staff',
  business: business
)

booking = Booking.create!(
  tenant_customer: customer,
  service: service,
  business: business,
  staff_member: staff_member,
  start_time: Time.current + 1.day,
  end_time: Time.current + 1.day + 1.hour,
  status: 'confirmed'
)

# Queue a notification that should be replayed after opt-in
pending_notification = PendingSmsNotification.queue_booking_notification(
  'booking_confirmation',
  booking,
  {
    customer_name: customer.first_name,
    service_name: service.name,
    business_name: business.name,
    date: booking.start_time.strftime('%m/%d/%Y'),
    time: booking.start_time.strftime('%I:%M %p')
  }
)

puts "Step 2: Created pending notification"
puts "  Pending notification ID: #{pending_notification.id}"
puts "  Type: #{pending_notification.notification_type}"
puts "  Status: #{pending_notification.status}"
puts

# Step 3: Simulate the webhook call
puts "Step 3: Simulating webhook processing..."

# Create controller instance and simulate the webhook call
controller = Webhooks::TwilioController.new

# Mock the request to avoid having to set up full Rails request context
def controller.request
  @mock_request ||= OpenStruct.new(
    headers: {},
    original_url: 'https://bizblasts.com/webhooks/twilio/inbound',
    raw_post: 'From=%2B15551234567&Body=YES'
  )
end

def controller.params
  @mock_params ||= {
    'From' => '+15551234567',
    'Body' => 'YES',
    'MessageSid' => 'SM123456789'
  }
end

def controller.render(options)
  puts "  Controller would render: #{options}"
end

# Simulate the inbound message processing
begin
  controller.send(:inbound_message)
  puts "  ✅ Webhook processing completed successfully"
rescue => e
  puts "  ❌ Webhook processing failed: #{e.message}"
  puts "     #{e.backtrace.first(3).join("\n     ")}"
end
puts

# Step 4: Verify results
puts "Step 4: Verifying results..."

# Check if customer was opted in
customer.reload
puts "  Customer opt-in status after webhook: #{customer.phone_opt_in?}"
puts "  Customer opt-in timestamp: #{customer.phone_opt_in_at}"

# Check if confirmation SMS was sent
confirmation_sms = SmsMessage.where(phone_number: customer.phone, content: /subscribed/).last
if confirmation_sms
  puts "  ✅ Confirmation SMS sent: #{confirmation_sms.content[0..60]}..."
  puts "     Status: #{confirmation_sms.status}"
else
  puts "  ❌ No confirmation SMS found"
end

# Check if pending notification was processed
pending_notification.reload
puts "  Pending notification status after webhook: #{pending_notification.status}"

# Check if notification was replayed
replayed_sms = SmsMessage.where(phone_number: customer.phone).where.not(content: /subscribed/).last
if replayed_sms
  puts "  ✅ Notification replayed: #{replayed_sms.content[0..60]}..."
  puts "     Status: #{replayed_sms.status}"
else
  puts "  ❌ No replayed notification found"
end

puts
puts "=== Test Summary ==="
puts "Customer opt-in: #{customer.phone_opt_in? ? '✅' : '❌'}"
puts "Confirmation sent: #{confirmation_sms ? '✅' : '❌'}"
puts "Notification replayed: #{replayed_sms ? '✅' : '❌'}"
puts
puts "Total SMS messages sent: #{SmsMessage.where(phone_number: customer.phone).count}"
SmsMessage.where(phone_number: customer.phone).each_with_index do |sms, index|
  puts "  #{index + 1}. #{sms.content[0..60]}... (#{sms.status})"
end