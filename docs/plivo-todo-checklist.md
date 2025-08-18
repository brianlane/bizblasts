# Plivo SMS Integration - Implementation Checklist

## Phase 1: Dependencies & Configuration

- [ ] Add Plivo gem to Gemfile: `gem 'plivo', '~> 4.59'`
- [ ] Run `bundle install`
- [ ] Create `config/initializers/plivo.rb` with environment variable validation:
  ```ruby
  PLIVO_AUTH_ID = ENV.fetch('PLIVO_AUTH_ID') { raise 'PLIVO_AUTH_ID not set' }
  PLIVO_AUTH_TOKEN = ENV.fetch('PLIVO_AUTH_TOKEN') { raise 'PLIVO_AUTH_TOKEN not set' }
  PLIVO_SOURCE_NUMBER = ENV.fetch('PLIVO_SOURCE_NUMBER') { raise 'PLIVO_SOURCE_NUMBER not set' }
  ```
- [ ] Update `.env.example` with required Plivo environment variables
- [ ] Update README with Plivo environment variables and setup instructions
- [ ] Remove `config/initializers/twilio.rb` file (cleanup)

## Phase 2: Data Model Updates

- [ ] Add `:plivo` to `IntegrationCredential.provider` enum (requires migration)
- [ ] Create migration for the enum update
- [ ] Update factories/specs to use `:plivo` provider where appropriate
- [ ] Remove any Twilio-related provider references from specs

## Phase 3: Core SMS Implementation

### 3.1 Refactor SmsService.send_message
- [ ] Replace placeholder code with `Plivo::RestClient.new.messages.create`
- [ ] Capture `response.message_uuid.first` as `external_id`
- [ ] Update `SmsMessage` status to `:sent` or `:failed` based on response
- [ ] Handle Plivo exceptions gracefully
- [ ] Remove all commented Twilio code
- [ ] Use shared `PLIVO_SOURCE_NUMBER` from environment (no per-business credentials)

### 3.2 Update SmsNotificationJob
- [ ] Remove placeholder `puts` statements
- [ ] Delegate to `SmsService.send_message`
- [ ] Fix `customer_id` vs `tenant_customer_id` inconsistency in line 89
- [ ] Remove all commented Twilio code and references

### 3.3 Update Sms::DeliveryProcessor
- [ ] Refactor to delegate to `SmsService` or deprecate in favor of the service
- [ ] Replace placeholder implementations with real Plivo integration
- [ ] Remove Twilio-related code

## Phase 4: Webhook Implementation

### 4.1 Create Plivo Webhook Controller
- [ ] Create `app/controllers/webhooks/plivo_controller.rb`
- [ ] Implement `delivery_receipt` action to handle delivery status updates
- [ ] Locate `SmsMessage` by `MessageUUID` parameter
- [ ] Update status based on Plivo webhook payload
- [ ] **REQUIRED**: Implement Plivo webhook signature verification for security
- [ ] Handle unknown message UUIDs gracefully

### 4.2 Add Webhook Routes
- [ ] Add webhook route: `post '/webhooks/plivo', to: 'webhooks/plivo#delivery_receipt'`
- [ ] Document webhook URL format for Plivo dashboard configuration

### 4.3 Plivo Dashboard Configuration
- [ ] Configure Plivo webhook URL in Plivo dashboard to point to the new endpoint
- [ ] Set up delivery receipt notifications in Plivo

## Phase 5: Testing

### 5.1 Unit Tests for SmsService
- [ ] Mock `Plivo::Resources::Messages#create` responses using WebMock/RSpec
- [ ] Test success scenarios with proper external_id capture
- [ ] Test failure scenarios with error message handling
- [ ] Test external_id capture and status updates
- [ ] Remove any Twilio-related test mocks

### 5.2 Request Specs for Webhooks::PlivoController
- [ ] Test delivery receipt processing (happy path)
- [ ] Test unknown message UUID handling
- [ ] Test invalid webhook data scenarios
- [ ] Test webhook signature verification (valid and invalid signatures)
- [ ] Test various Plivo delivery status values

### 5.3 Integration Testing
- [ ] Update existing SMS specs to work with new Plivo implementation
- [ ] Update factories to use `:plivo` provider instead of `:twilio`
- [ ] Ensure test suite passes with Plivo integration
- [ ] Remove Twilio-related test scenarios

## Phase 6: Environment & Deployment

- [ ] Update production environment with Plivo credentials
- [ ] Add health check integration - verify Plivo credentials on boot
- [ ] Ensure Sidekiq/ActiveJob compatibility - background jobs can access ENV variables
- [ ] Remove any Twilio-related environment variables from production

## Phase 7: Code Cleanup

- [ ] Remove all commented Twilio code from `SmsService`
- [ ] Remove all commented Twilio code from `SmsNotificationJob`
- [ ] Remove `config/initializers/twilio.rb` if it exists
- [ ] Remove any Twilio gem references from Gemfile
- [ ] Update any documentation that references Twilio
- [ ] Remove Twilio provider from `IntegrationCredential` enum if not used elsewhere

## Key Implementation Notes

1. **Shared Sender ID**: All tenants use the same `PLIVO_SOURCE_NUMBER` from environment variables (no per-business credentials)
2. **No Two-Way SMS**: Following email architecture, no inbound SMS handling needed initially
3. **Status Tracking**: Existing `SmsMessage` model status enum (`pending`/`sent`/`delivered`/`failed`) works perfectly with Plivo
4. **Error Handling**: Robust error handling with `error_message` field population on failures
5. **Backwards Compatibility**: All existing helper methods (`send_booking_confirmation`, `send_booking_reminder`) will work unchanged
6. **Security**: Webhook signature verification is required for production security
7. **Tenant Isolation**: Businesses do not have access to Plivo credentials - only system-level configuration

## Verification Checklist

- [ ] All tests pass
- [ ] SMS can be sent successfully through Plivo
- [ ] Webhook delivery receipts update message status correctly
- [ ] No Twilio code remains in the codebase
- [ ] Environment variables are properly configured
- [ ] Webhook signature verification works
- [ ] Error scenarios are handled gracefully
- [ ] Background jobs process SMS correctly