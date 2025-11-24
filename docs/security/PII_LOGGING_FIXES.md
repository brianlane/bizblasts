# PII Logging Fixes

This document summarizes the fixes applied to prevent logging of Personally Identifiable Information (PII) in clear text, addressing CodeQL security alerts and improving overall application security.

## Background

GitHub Advanced Security (CodeQL) flagged multiple instances where sensitive customer information was being logged in clear text. While some logging is necessary for debugging and security monitoring, PII must be sanitized before being written to logs to comply with GDPR, CCPA, and general security best practices.

## Solution: SecureLogger

All PII logging now uses `SecureLogger` instead of `Rails.logger`. `SecureLogger` automatically sanitizes:
- **Email addresses**: `user@example.com` → `use***@***`
- **Phone numbers**: `555-123-4567` → `***-***-4567`
- **SSN**: `123-45-6789` → `[REDACTED_SSN]`
- **Credit cards**: `4111-1111-1111-1111` → `[REDACTED_CREDIT_CARD]`
- **API keys**: Long strings → `[REDACTED_API_KEY]`

## Files Modified

### Models

#### app/models/customer_subscription.rb
- **Line 340**: Removed billing date from log message
  - **Before**: `"Advanced billing date for subscription #{id} to #{new_billing_date}"`
  - **After**: `"Advanced billing date for subscription #{id}"`
  - **Rationale**: Billing dates reveal customer subscription patterns (PII)

#### app/models/tenant_customer.rb
- **Lines 384, 386**: Changed `Rails.logger` to `SecureLogger` for email preference logs
- **Lines 407, 409**: Changed `Rails.logger` to `SecureLogger` for customer notification logs
  - These log `full_name` and `email`, both of which are PII

#### app/models/business.rb
- **Line 756**: Changed `Rails.logger` to `SecureLogger` and removed address from log
  - **Before**: `"Failed to look up timezone for #{full_address}: #{e.message}"`
  - **After**: `"Failed to look up timezone for address: #{e.message}"`
  - **Rationale**: Full addresses are PII

### Services

#### app/services/availability_service.rb
- **Line 93**: Removed specific booking date from debug log
  - **Before**: `"Max daily bookings reached for date #{booking_date}"`
  - **After**: `"Max daily bookings reached for requested date"`
- **Lines 150, 156**: Removed specific dates from policy violation logs
  - Dates reveal customer booking patterns

#### app/services/customer_conflict_resolver.rb
- **Line 80**: Changed `Rails.logger` to `SecureLogger` for email conflict errors
- **Line 110**: Changed `Rails.logger` to `SecureLogger` for phone conflict errors
  - These log email addresses and phone numbers directly

### Controllers

#### app/controllers/client_bookings_controller.rb
- **Lines 137, 149**: Changed `Rails.logger` to `SecureLogger` for security warnings
  - These log `current_user.email` for unauthorized access attempts

#### app/controllers/public/orders_controller.rb
- **Lines 321, 328**: Changed `Rails.logger` to `SecureLogger` for security warnings
  - Log both user emails and customer emails

#### app/controllers/public/booking_controller.rb
- **Line 434**: Changed `Rails.logger` to `SecureLogger` for security warning
  - Logs user and customer emails

#### app/controllers/orders_controller.rb
- **Lines 28, 40, 45, 59**: Changed `Rails.logger` to `SecureLogger` for security warnings
  - Multiple instances logging user and customer emails

### Jobs

#### app/jobs/cross_domain_logout_job.rb
- **Line 65**: Changed `Rails.logger` to `SecureLogger` for logout event
  - Logs user email and IP address

#### app/jobs/blog_notification_job.rb
- **Lines 25, 27**: Changed `Rails.logger` to `SecureLogger` for notification logs
  - Logs user email addresses

### Additional Controllers

#### app/controllers/business/registrations_controller.rb
- **Line 443**: Changed `Rails.logger` to `SecureLogger` for policy acceptance logging
  - Logs user email

#### app/controllers/client/registrations_controller.rb
- **Lines 63, 65, 83**: Changed `Rails.logger` to `SecureLogger` for referral and policy acceptance logs
  - Logs user email addresses

#### app/controllers/admin/booking_availability_controller.rb
- **Line 18**: Changed `Rails.logger` to `SecureLogger` for admin security warning
  - Logs admin user email

#### app/controllers/contacts_controller.rb
- **Line 39**: Changed `Rails.logger` to `SecureLogger` for contact form submissions
  - Logs contact submitter email

### Additional Services

#### app/services/booking_manager.rb
- **Line 327**: Changed `Rails.logger` to `SecureLogger` for manager override logging
  - Logs current user email

#### app/services/domain_removal_service.rb
- **Line 194**: Changed `Rails.logger` to `SecureLogger` for removal confirmation
  - Logs owner email

### Mailers

#### app/mailers/review_request_mailer.rb
- **Line 68**: Changed `Rails.logger` to `SecureLogger` for error logging
  - Logs customer email

#### app/mailers/invoice_mailer.rb
- **Lines 12, 20, 23, 37**: Changed `Rails.logger` to `SecureLogger` for invoice email logging
  - Logs customer email addresses

### Additional Models

#### app/models/payment.rb
- **Line 63**: Changed `Rails.logger` to `SecureLogger` for refund initiation
  - Logs user email

## Testing

All modified files pass linter checks. Key test suites to verify:
- `spec/security/secure_logger_spec.rb` - Confirms sanitization works
- `spec/security/tenant_isolation_spec.rb` - Includes data sanitization tests
- Controller and service specs for modified files

## Impact

### Security
- ✅ No PII stored in clear text in logs
- ✅ Maintains security monitoring capabilities with sanitized data
- ✅ Complies with GDPR/CCPA requirements for data minimization

### Debugging
- ✅ User/customer IDs still logged for debugging
- ✅ Business context (business ID, tenant) still available
- ✅ Last 4 digits of phone numbers visible for pattern matching
- ✅ Partial email addresses (first 3 chars) help identify users

### CodeQL Alerts
- ✅ Resolves "Clear-text storage of sensitive information" alerts
- ✅ Prevents future false positives by using `SecureLogger` consistently

## Best Practices Going Forward

1. **Always use `SecureLogger`** for any logs that might contain:
   - Email addresses
   - Phone numbers
   - Physical addresses
   - Billing/payment information
   - Date-based patterns that reveal customer behavior

2. **Use IDs instead of values** where possible:
   - Log `user_id` instead of `user.email`
   - Log `business_id` instead of `business.name` (when sensitive)
   - Log record existence without specific values

3. **Debug logs**: Even debug-level logs should avoid PII, as log level configurations can change

4. **Security logs**: Security monitoring logs MUST use `SecureLogger` since they're often long-lived and analyzed by multiple systems

## Related Documentation

- `docs/security/phone-number-encryption.md` - Phone number encryption implementation
- `docs/security/ENCRYPTION_CLEANUP_SUMMARY.md` - Database encryption cleanup
- `app/lib/secure_logger.rb` - SecureLogger implementation
- `spec/security/secure_logger_spec.rb` - SecureLogger tests

