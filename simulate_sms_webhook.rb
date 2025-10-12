#!/usr/bin/env ruby
# Simulate SMS webhook processing for testing
# Usage: rails runner simulate_sms_webhook.rb [YES|STOP|HELP|START]

puts "=" * 80
puts "SMS WEBHOOK SIMULATOR"
puts "=" * 80

phone_number = '+16026866672'
message_body = ARGV[0]&.upcase || 'YES'

puts "Phone Number: #{phone_number}"
puts "Simulated Message: #{message_body}"
puts "Time: #{Time.current}"
puts "=" * 80

# Validate message
valid_messages = ['YES', 'Y', 'STOP', 'UNSUBSCRIBE', 'START', 'UNSTOP', 'HELP']
unless valid_messages.include?(message_body)
  puts "\n❌ Invalid message: #{message_body}"
  puts "Valid messages: #{valid_messages.join(', ')}"
  puts "\nUsage: rails runner simulate_sms_webhook.rb [message]"
  puts "Example: rails runner simulate_sms_webhook.rb YES"
  exit 1
end

# Find customer
customer = TenantCustomer.find_by(phone: phone_number)

unless customer
  puts "\n❌ No customer found with phone number #{phone_number}"
  exit 1
end

business = customer.business

puts "\n=== Before Processing ==="
puts "Customer: #{customer.full_name}"
puts "Business: #{business.name}"
puts "Current opt-in status: #{customer.phone_opt_in? ? 'OPTED IN' : 'OPTED OUT'}"
puts "Phone opt-in at: #{customer.phone_opt_in_at}"
puts "Phone marketing opt-out: #{customer.phone_marketing_opt_out? ? 'YES' : 'NO'}"

puts "\n=== Processing Webhook Simulation ==="
puts "Simulating: Customer replies '#{message_body}' to #{business.name}"

# Process the webhook message using the same logic as the controller
case message_body
when 'YES', 'Y'
  puts "\n📝 Processing OPT-IN..."

  # Check for pending invitations
  invitation = SmsOptInInvitation.find_by(
    phone_number: phone_number,
    responded_at: nil
  )

  if invitation
    puts "  Found pending invitation (ID: #{invitation.id})"
    puts "  Business: #{invitation.business.name}"
    puts "  Context: #{invitation.context}"

    # Mark invitation as responded
    invitation.update!(responded_at: Time.current)
    puts "  ✅ Invitation marked as responded"
  else
    puts "  ⚠️  No pending invitation found (still processing opt-in)"
  end

  # Opt customer in
  customer.opt_into_sms!
  puts "  ✅ Customer opted into SMS"

  # Send confirmation
  confirmation_message = "You're now subscribed to #{business.name} SMS notifications. Reply STOP to unsubscribe or HELP for assistance."
  result = SmsService.send_message(phone_number, confirmation_message, {
    business_id: business.id,
    tenant_customer_id: customer.id,
    message_type: :opt_in_confirmation
  })

  if result[:success]
    puts "  ✅ Confirmation SMS sent"
  else
    puts "  ❌ Failed to send confirmation: #{result[:error]}"
  end

when 'STOP', 'UNSUBSCRIBE'
  puts "\n📝 Processing OPT-OUT..."

  # Opt customer out
  customer.opt_out_of_sms!
  puts "  ✅ Customer opted out of SMS"

  # Add business-specific opt-out
  customer.opt_out_from_business!(business)
  puts "  ✅ Business opt-out added"

  # Send confirmation
  confirmation_message = "You have been unsubscribed from #{business.name} SMS notifications. Reply START to re-subscribe or HELP for assistance."
  result = SmsService.send_message(phone_number, confirmation_message, {
    business_id: business.id,
    tenant_customer_id: customer.id,
    message_type: :opt_out_confirmation
  })

  if result[:success]
    puts "  ✅ Confirmation SMS sent"
  else
    puts "  ❌ Failed to send confirmation: #{result[:error]}"
  end

when 'START', 'UNSTOP'
  puts "\n📝 Processing RE-OPT-IN..."

  # Re-opt customer in
  customer.opt_into_sms!
  puts "  ✅ Customer re-opted into SMS"

  # Remove business-specific opt-out
  if customer.opted_out_from_business?(business)
    customer.opt_in_to_business!(business)
    puts "  ✅ Business opt-out removed"
  else
    puts "  ℹ️  No business opt-out to remove"
  end

  # Send confirmation
  confirmation_message = "You have been re-subscribed to #{business.name} SMS notifications. Reply STOP to unsubscribe or HELP for assistance."
  result = SmsService.send_message(phone_number, confirmation_message, {
    business_id: business.id,
    tenant_customer_id: customer.id,
    message_type: :opt_in_confirmation
  })

  if result[:success]
    puts "  ✅ Confirmation SMS sent"
  else
    puts "  ❌ Failed to send confirmation: #{result[:error]}"
  end

when 'HELP'
  puts "\n📝 Processing HELP request..."

  help_message = "#{business.name} SMS Help: Reply YES to subscribe, STOP to unsubscribe, or contact us at #{business.email}."
  result = SmsService.send_message(phone_number, help_message, {
    business_id: business.id,
    tenant_customer_id: customer.id,
    message_type: :help
  })

  if result[:success]
    puts "  ✅ Help message sent"
  else
    puts "  ❌ Failed to send help message: #{result[:error]}"
  end

  puts "  ℹ️  No opt-in status change for HELP messages"
end

# Reload customer to get updated data
customer.reload

puts "\n=== After Processing ==="
puts "New opt-in status: #{customer.phone_opt_in? ? '✅ OPTED IN' : '❌ OPTED OUT'}"
puts "Phone opt-in at: #{customer.phone_opt_in_at}"
puts "Phone marketing opt-out: #{customer.phone_marketing_opt_out? ? '✅ YES' : '❌ NO'}"
puts "Can receive SMS: #{customer.can_receive_sms?(:booking) ? '✅ YES' : '❌ NO'}"

puts "\n" + "=" * 80
puts "SIMULATION COMPLETE"
puts "=" * 80

puts "\nTo verify the changes persisted, run:"
puts "  rails runner check_sms_webhook_status.rb"
puts "\nTo test different responses, run:"
puts "  rails runner simulate_sms_webhook.rb YES     # Opt in"
puts "  rails runner simulate_sms_webhook.rb STOP    # Opt out"
puts "  rails runner simulate_sms_webhook.rb START   # Re-opt in"
puts "  rails runner simulate_sms_webhook.rb HELP    # Get help"
puts "=" * 80
