# Webhook Signature Verification Recovery Plan

## Current State
- Signature verification temporarily disabled (`TWILIO_VERIFY_SIGNATURES=false`)
- Customer opt-in working but with silent failures in follow-up actions
- Need to re-enable signature verification with proper URL handling

## Phase 1: Fix Silent Failures (IMMEDIATE)
1. **Debug webhook processing failures**
   - Run `debug_webhook_failures.rb` to identify exact failure points
   - Fix SmsService errors preventing confirmation messages
   - Fix notification replay job failures

2. **Improve error handling**
   - Replace silent `rescue` blocks with proper error logging
   - Add monitoring/alerting for webhook processing failures
   - Ensure critical failures are visible

## Phase 2: Fix Signature Validation (NEXT)
1. **Root cause analysis**
   - Compare `request.original_url` with Twilio's signature calculation URL
   - Check if redirects from `bizblasts.com` to `www.bizblasts.com` affect signatures
   - Verify Twilio auth token matches between console and Rails

2. **URL handling fixes**
   ```ruby
   def valid_signature?
     signature = request.headers['X-Twilio-Signature']
     return false unless signature

     # Use the URL Twilio actually called (before any redirects)
     url = request.original_url
     body = request.raw_post

     # Debug logging
     Rails.logger.info "[WEBHOOK] Signature validation: URL=#{url}, Signature=#{signature[0..10]}..."

     validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
     result = validator.validate(url, body, signature)

     Rails.logger.info "[WEBHOOK] Signature validation result: #{result}"
     result
   end
   ```

3. **Twilio configuration verification**
   - Ensure webhook URL in Twilio console matches Rails routes exactly
   - Verify auth token consistency
   - Test signature validation in staging environment first

## Phase 3: Re-enable Signature Verification (FINAL)
1. **Gradual rollout**
   ```ruby
   def verify_webhook_signature?
     case ENV['TWILIO_SIGNATURE_MODE']
     when 'disabled'
       false
     when 'log_only'  # Log validation results but don't enforce
       true_but_dont_reject = true
       false
     when 'enforced'
       Rails.env.production?
     else
       Rails.env.production? && ENV['TWILIO_VERIFY_SIGNATURES'] != 'false'
     end
   end
   ```

2. **Monitoring and rollback plan**
   - Monitor webhook success rates after re-enabling
   - Have immediate rollback capability
   - Alert on signature validation failures

## Testing Strategy
1. **Local testing**: Use RSpec mocks in `spec/requests/webhooks/twilio_inbound_spec.rb`
2. **Staging testing**: Test with real Twilio webhooks in staging environment
3. **Production testing**: Gradual rollout with monitoring

## Environment Variables
```
# Current (temporary)
TWILIO_VERIFY_SIGNATURES=false

# Future phases
TWILIO_SIGNATURE_MODE=disabled|log_only|enforced
```

## Success Criteria
1. Customer opt-in flow works end-to-end
2. Confirmation messages sent reliably
3. Pending notifications replayed successfully
4. Signature verification enabled and working
5. No silent failures in webhook processing