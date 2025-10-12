#!/usr/bin/env ruby
# Check SMS webhook processing status
# Usage: rails runner check_sms_webhook_status.rb

puts "=" * 80
puts "SMS WEBHOOK STATUS CHECKER"
puts "=" * 80
puts "Phone Number: +16026866672"
puts "Time: #{Time.current}"
puts "=" * 80

phone_number = '+16026866672'

# Find customer
customer = TenantCustomer.find_by(phone: phone_number)

unless customer
  puts "\n❌ No customer found with phone number #{phone_number}"
  exit 1
end

customer.reload  # Refresh from database
business = customer.business

puts "\n=== Customer Information ==="
puts "ID: #{customer.id}"
puts "Name: #{customer.full_name}"
puts "Business: #{business.name}"
puts "Email: #{customer.email}"
puts "Phone: #{customer.phone}"

puts "\n=== Current Opt-in Status ==="
puts "Phone Opt-in: #{customer.phone_opt_in? ? '✅ YES' : '❌ NO'}"
puts "Phone Opt-in At: #{customer.phone_opt_in_at || 'Never'}"
puts "Phone Marketing Opt-out: #{customer.phone_marketing_opt_out? ? '✅ YES' : '❌ NO'}"

puts "\n=== SMS Receiving Capabilities ==="
puts "Can receive booking SMS: #{customer.can_receive_sms?(:booking) ? '✅' : '❌'}"
puts "Can receive payment SMS: #{customer.can_receive_sms?(:payment) ? '✅' : '❌'}"
puts "Can receive review request SMS: #{customer.can_receive_sms?(:review_request) ? '✅' : '❌'}"

puts "\n=== Recent SMS Messages (Last 10) ==="
recent_messages = SmsMessage.where(phone_number: phone_number).order(created_at: :desc).limit(10)
if recent_messages.any?
  recent_messages.each_with_index do |msg, index|
    puts "\n#{index + 1}. [#{msg.created_at.strftime('%Y-%m-%d %H:%M:%S')}]"
    puts "   Status: #{msg.status}"
    puts "   Content: #{msg.content}"
    puts "   Business: #{msg.business&.name || 'N/A'}"
    puts "   Sent at: #{msg.sent_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Not sent'}"
    puts "   Delivered at: #{msg.delivered_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Not delivered'}"
  end
else
  puts "No SMS messages found"
end

puts "\n=== Recent Opt-in Invitations ==="
invitations = SmsOptInInvitation.where(phone_number: phone_number).order(created_at: :desc).limit(5)
if invitations.any?
  invitations.each_with_index do |inv, index|
    puts "\n#{index + 1}. [#{inv.created_at.strftime('%Y-%m-%d %H:%M:%S')}]"
    puts "   Context: #{inv.context}"
    puts "   Business: #{inv.business.name}"
    puts "   Responded At: #{inv.responded_at || 'Not responded'}"
  end
else
  puts "No opt-in invitations found"
end

puts "\n=== Business-Specific Opt-outs ==="
opted_out_businesses = customer.sms_opted_out_businesses || []
if opted_out_businesses.any?
  puts "Customer has opted out from #{opted_out_businesses.length} business(es):"
  opted_out_businesses.each_with_index do |business_id, index|
    business = Business.find_by(id: business_id)
    puts "  #{index + 1}. Business ID: #{business_id} (#{business&.name || 'Unknown'})"
  end
else
  puts "No business-specific opt-outs"
end

puts "\n=== SMS Configuration ==="
sms_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SMS', 'true'))
puts "Global SMS Enabled: #{sms_enabled ? '✅' : '❌'}"

puts "\n=== Summary ==="
if customer.phone_opt_in?
  puts "✅ Customer is OPTED IN to SMS notifications"
  puts "   They will receive SMS for:"
  puts "   - Booking confirmations and reminders" if customer.can_receive_sms?(:booking)
  puts "   - Payment confirmations" if customer.can_receive_sms?(:payment)
  puts "   - Review requests" if customer.can_receive_sms?(:review_request)
else
  puts "❌ Customer is NOT opted in to SMS notifications"
  puts "   They will NOT receive SMS messages"
end

puts "\n" + "=" * 80
puts "WEBHOOK STATUS CHECK COMPLETE"
puts "=" * 80

puts "\nExpected webhook behavior:"
puts "- Reply 'YES' or 'Y' → Should opt customer IN"
puts "- Reply 'STOP' or 'UNSUBSCRIBE' → Should opt customer OUT"
puts "- Reply 'START' or 'UNSTOP' → Should opt customer back IN"
puts "- Reply 'HELP' → Should send help message (no status change)"
puts "\nIf you replied and don't see changes, check:"
puts "1. Webhook endpoint is accessible: #{ENV['APP_HOST'] || 'localhost'}/webhooks/twilio/sms"
puts "2. Twilio webhook is configured to POST to that URL"
puts "3. Check Rails logs for webhook requests: tail -f log/production.log | grep Twilio"
puts "=" * 80
