puts "=== REAL SMS END-TO-END TEST ==="
puts "This script will send a real SMS invitation and guide you through testing"
puts

# Step 1: Prepare test customer
puts "📋 STEP 1: PREPARING FOR REAL SMS TEST"

customer = TenantCustomer.find_by(phone: '+16026866672')
business = customer&.business

if !customer || !business
  puts "❌ Test customer or business not found"
  exit 1
end

puts "Customer: #{customer.first_name} #{customer.last_name} (ID: #{customer.id})"
puts "Business: #{business.name} (ID: #{business.id})"
puts "Current opt-in status: #{customer.phone_opt_in?}"
puts

# Step 2: Opt out customer for clean test
if customer.phone_opt_in?
  customer.update!(phone_opt_in: false, phone_opt_in_at: nil)
  puts "✅ Opted out customer for clean test"
end

# Step 3: Create some pending notifications to test replay
puts "📋 STEP 2: CREATING TEST PENDING NOTIFICATIONS"

# Create a booking for notification testing
service = Service.where(business: business).first
unless service
  service = Service.create!(
    name: 'Test Service for SMS',
    business: business,
    duration: 60,
    price: 100
  )
  puts "✅ Created test service: #{service.name}"
end

booking = Booking.create!(
  tenant_customer: customer,
  service: service,
  business: business,
  start_time: Time.current + 1.day,
  status: 'confirmed'
)
puts "✅ Created test booking: #{booking.id}"

# Create a pending notification
pending_notification = PendingSmsNotification.create!(
  tenant_customer: customer,
  business: business,
  notification_type: 'booking_confirmation',
  context: { booking_id: booking.id },
  status: 'pending'
)
puts "✅ Created pending notification: #{pending_notification.id}"

# Step 4: Send invitation
puts "📋 STEP 3: SENDING REAL SMS INVITATION"

# Clear any recent invitations first
SmsOptInInvitation.where(phone_number: customer.phone)
                  .where('created_at > ?', 1.hour.ago)
                  .delete_all

result = SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)

if result[:success]
  puts "✅ SMS invitation sent successfully!"
  puts "Twilio SID: #{result[:twilio_sid]}"
else
  puts "❌ SMS invitation failed: #{result[:error]}"
  exit 1
end

puts
puts "📱 STEP 4: MANUAL TESTING INSTRUCTIONS"
puts "=============================================="
puts "1. Check your phone for the SMS invitation"
puts "2. Reply 'YES' to the invitation"
puts "3. Wait 10-15 seconds for processing"
puts "4. You should receive a confirmation SMS"
puts "5. Run the verification script to check results"
puts
puts "Expected flow:"
puts "  📱 You: Receive invitation SMS"
puts "  📱 You: Reply 'YES'"
puts "  🔄 Twilio: Calls webhook with your reply"
puts "  ✅ System: Processes opt-in"
puts "  📱 You: Receive confirmation SMS"
puts "  📱 You: Receive booking confirmation (pending notification replay)"
puts
puts "After testing, run: bundle exec rails runner test_results.rb"

# Record test start time for verification
File.write('/tmp/sms_test_start_time', Time.current.to_f.to_s)