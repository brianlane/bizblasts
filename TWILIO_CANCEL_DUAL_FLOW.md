# Twilio CANCEL Keyword Dual Flow Implementation

## Problem Statement

Twilio treats `CANCEL` as a default opt-out keyword (part of STOP synonyms) starting in 2025. When a customer sends "CANCEL", Twilio automatically marks the number as opted-out at the carrier level. This created a state mismatch where:

1. **Application behavior**: CANCEL cancels the booking, customer remains opted-in
2. **Twilio behavior**: CANCEL triggers carrier-level opt-out
3. **Result**: Future SMS attempts fail with "21610" errors because Twilio blocks delivery to opted-out numbers

## Solution: Dual Flow Implementation

To keep application state in sync with Twilio's carrier-level opt-out, we implemented a **dual flow** where CANCEL both cancels the booking AND records the opt-out in the application database.

### Implementation Details

#### app/controllers/webhooks/twilio_controller.rb

The `process_booking_cancellation` method now implements two distinct flows:

**Flow 1: Booking Cancellation Succeeds**
```ruby
1. Cancel the booking via BookingManager
2. Send cancellation notification (email + SMS) via NotificationService
3. Record opt-out in database via process_sms_opt_out
4. Send separate opt-out confirmation SMS

Result: Customer receives 2 SMS messages
- "Your booking has been cancelled..."
- "You've been unsubscribed from [Business] SMS. Reply START to re-subscribe."
```

**Flow 2: No Booking or Cancellation Fails**
```ruby
1. Send combined message explaining error AND confirming opt-out
2. Record opt-out in database with skip_auto_reply: true

Result: Customer receives 1 SMS message
- "You don't have any upcoming bookings. You've been unsubscribed from SMS. Reply START to re-subscribe."
- OR "Sorry, it's too late to cancel. You've been unsubscribed from SMS. Reply START to re-subscribe."
```

### Key Changes

1. **process_booking_cancellation** (lines 266-360)
   - Always calls `process_sms_opt_out` to record opt-out in database
   - Success path: Separate cancellation + opt-out messages
   - Error path: Combined message for better UX

2. **process_sms_opt_out** (lines 176-220)
   - Added `skip_auto_reply` parameter
   - When `skip_auto_reply: true`, records opt-out without sending SMS
   - Used when combined message already sent to customer

### Benefits

✅ **State Consistency**: Application state matches Twilio's carrier-level opt-out status
✅ **Prevents 21610 Errors**: Future SMS sends won't fail due to state mismatch
✅ **Works With Any Twilio Configuration**:
   - Works if Advanced Opt-Out configured to remove CANCEL from synonyms
   - Works if CANCEL remains a default opt-out keyword
✅ **Better UX**: Combined messages reduce confusion when booking cancellation fails

### Test Coverage

Added comprehensive test coverage in `spec/requests/webhooks/twilio_inbound_keywords_spec.rb`:

- ✅ Dual flow behavior verification
- ✅ Opt-out happens even when booking cancellation succeeds
- ✅ Opt-out happens even when no booking exists
- ✅ Opt-out happens even when cancellation fails
- ✅ Global opt-in maintained (business-specific opt-out only)
- ✅ Correct number of SMS messages sent in each scenario
- ✅ Combined messages include both error explanation and opt-out confirmation

**Test Results**: 184 examples, 0 failures

### FCC Compliance

This implementation maintains FCC compliance with SMS opt-out requirements:
- STOP, START, and HELP keywords cannot be removed (required for compliance)
- CANCEL is a secondary keyword that Twilio treats as opt-out synonym
- Our dual flow ensures we honor Twilio's opt-out behavior
- Customers can re-subscribe by texting START

### Future Considerations

If the business wants CANCEL to ONLY cancel bookings without opt-out:
1. Configure Twilio Advanced Opt-Out for your Messaging Service
2. Remove CANCEL from the STOP synonyms list
3. The dual flow will still work but won't send opt-out messages
4. Requires access to Twilio account settings

### Related Files

- `app/controllers/webhooks/twilio_controller.rb` - Main implementation
- `spec/requests/webhooks/twilio_inbound_keywords_spec.rb` - Test coverage
- `spec/requests/webhooks/twilio_opt_out_edge_cases_spec.rb` - Edge case tests
- `spec/requests/webhooks/twilio_enhanced_spec.rb` - Enhanced tests
- `spec/controllers/webhooks/twilio_controller_business_opt_out_spec.rb` - Business opt-out tests

### Documentation References

- Twilio Opt-Out Keywords: https://support.twilio.com/hc/en-us/articles/1260803225669-Advanced-Opt-Out-for-Messaging-Services
- FCC Requirements: https://www.twilio.com/blog/fcc-compliance-messaging-10dlc
