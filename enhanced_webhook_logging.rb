puts "=== ENHANCED WEBHOOK LOGGING PATCH ==="
puts "This adds detailed logging to help debug signature verification"
puts

# Create a patch that enhances the webhook controller with detailed logging
patch_content = <<~RUBY
  # Enhanced logging for signature verification debugging
  # Add this temporarily to app/controllers/webhooks/twilio_controller.rb

  def valid_signature?
    # Twilio webhook signature verification with enhanced logging
    signature = request.headers['X-Twilio-Signature']

    Rails.logger.info "[WEBHOOK_DEBUG] ===== SIGNATURE VERIFICATION DEBUG ====="
    Rails.logger.info "[WEBHOOK_DEBUG] Request headers:"
    request.headers.each do |key, value|
      if key.start_with?('HTTP_') || key.include?('Twilio') || key.include?('Host') || key.include?('Forwarded')
        Rails.logger.info "[WEBHOOK_DEBUG]   #{key}: #{value}"
      end
    end

    Rails.logger.info "[WEBHOOK_DEBUG] X-Twilio-Signature: #{signature || 'MISSING'}"

    return false unless signature

    # Get URL and body with detailed logging
    reconstructed_url = reconstruct_original_url
    body = request.raw_post

    Rails.logger.info "[WEBHOOK_DEBUG] Request details:"
    Rails.logger.info "[WEBHOOK_DEBUG]   request.host: #{request.host}"
    Rails.logger.info "[WEBHOOK_DEBUG]   request.original_url: #{request.original_url}"
    Rails.logger.info "[WEBHOOK_DEBUG]   reconstructed_url: #{reconstructed_url}"
    Rails.logger.info "[WEBHOOK_DEBUG]   request.raw_post: #{body}"
    Rails.logger.info "[WEBHOOK_DEBUG]   body length: #{body.length}"

    # Log environment details
    Rails.logger.info "[WEBHOOK_DEBUG] Environment:"
    Rails.logger.info "[WEBHOOK_DEBUG]   Rails.env: #{Rails.env}"
    Rails.logger.info "[WEBHOOK_DEBUG]   TWILIO_AUTH_TOKEN present: #{ENV['TWILIO_AUTH_TOKEN'].present?}"
    Rails.logger.info "[WEBHOOK_DEBUG]   TWILIO_AUTH_TOKEN length: #{ENV['TWILIO_AUTH_TOKEN']&.length}"

    # Test signature validation
    begin
      validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
      result = validator.validate(reconstructed_url, body, signature)

      Rails.logger.info "[WEBHOOK_DEBUG] Signature validation:"
      Rails.logger.info "[WEBHOOK_DEBUG]   validator created: YES"
      Rails.logger.info "[WEBHOOK_DEBUG]   validation result: #{result}"

      # Try validation with different URL variations to identify the issue
      url_variations = [
        request.original_url,
        reconstructed_url,
        "https://bizblasts.com/webhooks/twilio/inbound",
        "https://www.bizblasts.com/webhooks/twilio/inbound"
      ].uniq

      Rails.logger.info "[WEBHOOK_DEBUG] Testing URL variations:"
      url_variations.each_with_index do |test_url, index|
        test_result = validator.validate(test_url, body, signature)
        Rails.logger.info "[WEBHOOK_DEBUG]   #{index + 1}. #{test_url} -> #{test_result}"
      end

      return result

    rescue => e
      Rails.logger.error "[WEBHOOK_DEBUG] Error in signature validation: #{e.message}"
      Rails.logger.error "[WEBHOOK_DEBUG] Backtrace: #{e.backtrace.first(3).join(', ')}"
      return false
    ensure
      Rails.logger.info "[WEBHOOK_DEBUG] ===== END SIGNATURE VERIFICATION DEBUG ====="
    end
  end
RUBY

puts "📋 ENHANCED LOGGING PATCH:"
puts "=========================="
puts patch_content
puts

puts "🔧 HOW TO APPLY THIS PATCH:"
puts "=========================="
puts
puts "1. BACKUP the current webhook controller:"
puts "   cp app/controllers/webhooks/twilio_controller.rb app/controllers/webhooks/twilio_controller.rb.backup"
puts
puts "2. REPLACE the 'valid_signature?' method (lines 285-312) with the enhanced version above"
puts
puts "3. SET signature verification to true in production:"
puts "   TWILIO_VERIFY_SIGNATURES=true"
puts
puts "4. DEPLOY and test with a single SMS reply"
puts
puts "5. CHECK production logs for '[WEBHOOK_DEBUG]' entries"
puts
puts "6. ANALYZE the logs to identify:"
puts "   - Which URL variation works (if any)"
puts "   - Whether headers are correct"
puts "   - If body is being modified"
puts
puts "7. RESTORE original method after debugging:"
puts "   mv app/controllers/webhooks/twilio_controller.rb.backup app/controllers/webhooks/twilio_controller.rb"
puts

puts "📊 WHAT TO LOOK FOR IN LOGS:"
puts "============================="
puts "✅ If one of the URL variations shows 'true' -> Use that URL format"
puts "❌ If all URL variations show 'false' -> Body or signature issue"
puts "🔍 Check for modified request bodies (proxy interference)"
puts "🔍 Check for missing X-Twilio-Signature header"
puts "🔍 Verify TWILIO_AUTH_TOKEN matches Twilio console exactly"
puts

puts "💡 COMMON FIXES BASED ON LOG RESULTS:"
puts "===================================="
puts "1. If 'https://bizblasts.com/webhooks/twilio/inbound' works:"
puts "   -> Add TWILIO_WEBHOOK_DOMAIN=bizblasts.com environment variable"
puts
puts "2. If body is being modified:"
puts "   -> Check middleware, proxies, load balancers"
puts
puts "3. If signature missing:"
puts "   -> Check proxy configuration, ensure headers pass through"
puts
puts "4. If all variations fail:"
puts "   -> Verify TWILIO_AUTH_TOKEN in production matches Twilio console"
puts

puts "🚀 READY TO DEBUG!"
puts "Apply the patch, deploy, test, and check logs!"