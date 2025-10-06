puts "=== PRODUCTION WEBHOOK DEPLOYMENT VERIFICATION ==="
puts "Checking if enhanced logging was actually deployed to production"
puts

# 1. Check if the webhook controller has our enhanced logging
puts "📋 WEBHOOK CONTROLLER STATUS:"
puts "================================"

controller_file = "/opt/render/project/src/app/controllers/webhooks/twilio_controller.rb"
if File.exist?(controller_file)
  content = File.read(controller_file)

  # Check for our debug logging markers
  has_debug_logging = content.include?("[WEBHOOK_DEBUG]")
  has_signature_method = content.include?("def valid_signature?")
  has_enhanced_error_handling = content.include?("SECURITY: Only validate against the exact URL")

  puts "✅ Webhook controller file exists"
  puts "Enhanced debug logging present: #{has_debug_logging ? '✅ YES' : '❌ NO'}"
  puts "Signature validation method exists: #{has_signature_method ? '✅ YES' : '❌ NO'}"
  puts "Enhanced security comments present: #{has_enhanced_error_handling ? '✅ YES' : '❌ NO'}"

  if has_debug_logging
    puts "\n🔍 Debug logging method preview:"
    lines = content.split("\n")
    debug_start = lines.index { |line| line.include?("def valid_signature?") }
    if debug_start
      preview_lines = lines[debug_start, 10]
      preview_lines.each_with_index do |line, idx|
        puts "  #{debug_start + idx + 1}: #{line}"
      end
    end
  end
else
  puts "❌ Webhook controller file not found at expected path"
end

puts "\n📋 ENVIRONMENT VARIABLES:"
puts "========================="
puts "TWILIO_VERIFY_SIGNATURES: #{ENV['TWILIO_VERIFY_SIGNATURES'] || 'NOT SET'}"
puts "TWILIO_WEBHOOK_DOMAIN: #{ENV['TWILIO_WEBHOOK_DOMAIN'] || 'NOT SET'}"
puts "TWILIO_AUTH_TOKEN present: #{ENV['TWILIO_AUTH_TOKEN'].present?}"
puts "TWILIO_ACCOUNT_SID present: #{ENV['TWILIO_ACCOUNT_SID'].present?}"

puts "\n📋 RAILS APPLICATION STATUS:"
puts "============================"
puts "Rails environment: #{Rails.env}"
puts "Application name: #{Rails.application.class.module_parent.name}"

# Check if webhook routes are accessible
puts "\n📋 WEBHOOK ROUTES:"
puts "=================="
begin
  webhook_routes = Rails.application.routes.routes.select do |route|
    route.path.spec.to_s.include?('/webhooks/twilio')
  end

  if webhook_routes.any?
    webhook_routes.each do |route|
      puts "✅ #{route.verb.ljust(8)} #{route.path.spec}"
    end
  else
    puts "❌ No Twilio webhook routes found"
  end
rescue => e
  puts "❌ Error checking routes: #{e.message}"
end

puts "\n📋 WEBHOOK CONTROLLER INSTANTIATION TEST:"
puts "========================================"
begin
  controller = Webhooks::TwilioController.new
  puts "✅ Webhook controller instantiated successfully"

  # Test if our debug method exists
  if controller.respond_to?(:valid_signature?, true)
    puts "✅ valid_signature? method exists"
  else
    puts "❌ valid_signature? method missing"
  end

  # Test if verify_webhook_signature? method exists
  if controller.respond_to?(:verify_webhook_signature?, true)
    verify_enabled = controller.send(:verify_webhook_signature?)
    puts "✅ verify_webhook_signature? method exists, returns: #{verify_enabled}"
  else
    puts "❌ verify_webhook_signature? method missing"
  end
rescue => e
  puts "❌ Error instantiating webhook controller: #{e.message}"
end

puts "\n💡 DEPLOYMENT VERIFICATION SUMMARY:"
puts "==================================="

# Check git commit info if available
begin
  if File.exist?('.git')
    current_commit = `git rev-parse HEAD`.strip[0..7]
    current_branch = `git rev-parse --abbrev-ref HEAD`.strip
    puts "Current commit: #{current_commit}"
    puts "Current branch: #{current_branch}"

    # Check if our target commit (7c41bac) is in the history
    target_commit = "7c41bac"
    commit_exists = `git log --oneline`.include?(target_commit)
    puts "Target commit #{target_commit} in history: #{commit_exists ? '✅ YES' : '❌ NO'}"
  end
rescue => e
  puts "Git info unavailable: #{e.message}"
end

puts "\n🎯 NEXT STEPS:"
puts "=============="
if !has_debug_logging
  puts "❌ ISSUE: Enhanced logging not deployed to production"
  puts "   → Deploy commit 7c41bac with enhanced webhook logging"
  puts "   → Verify deployment completed successfully"
else
  puts "✅ Enhanced logging appears to be deployed"
  puts "   → Issue may be with webhook infrastructure"
  puts "   → Proceed to test webhook accessibility"
end