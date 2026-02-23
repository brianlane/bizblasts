# DST Bug Fix Summary

## Issue
Both Cursor and Codex AI bots reported the same underlying bug with different manifestations:

### Cursor's Report: "Inconsistent end-time calculation between slots and booking"
- **Symptom**: During DST transitions, displayed slot end_time differs from booked end_time by 1 hour
- **Example**: Slot shows 10 AM → 10 AM next day, but booking creates 10 AM → 11 AM (during spring-forward)

### Codex's Report: "Preserve fixed-minute rental durations across DST shifts"
- **Symptom**: 1-day (1440 min) rental becomes 25 hours during fall-back DST, causing:
  - Pricing to calculate as 2 days instead of 1
  - Validation to reject rentals with `max_rental_duration_mins: 1440`

## Root Cause
**Inconsistent end-time calculation between slot generation and booking creation:**

- `RentalAvailabilityService.available_slots` used `advance(days:)` for exact-day multiday rentals
  - This respects DST: "1 day" = same clock time tomorrow (23-25 hours depending on DST)

- `RentalBookingService.requested_times` used `+ duration_mins.minutes`
  - This uses elapsed time: "1 day" = exactly 1440 minutes (regardless of DST)

- All pricing and validation logic also uses elapsed minutes

This created a mismatch where:
1. **Cursor's observation**: Displayed slots and actual bookings had different end times
2. **Codex's observation**: Pricing/validation calculated different durations than intended

## The Fix
**File**: `app/services/rental_availability_service.rb:147-148`

**Before** (lines 147-151):
```ruby
slot_end = if is_multiday && (duration_mins % (24 * 60)).zero?
  current_time.advance(days: duration_mins / (24 * 60))
else
  current_time + duration_mins.minutes
end
```

**After**:
```ruby
slot_end = current_time + duration_mins.minutes
```

## Rationale
Using **fixed-minute durations** throughout the system ensures:

1. ✅ **Consistency**: Slot display, booking creation, pricing, and validation all use the same calculation
2. ✅ **Predictable pricing**: A 1-day rental always costs the same, regardless of DST
3. ✅ **Correct validation**: `max_rental_duration_mins` works as expected
4. ✅ **Transparent behavior**: 1440 minutes = 1440 minutes, not 1380 or 1500

## Trade-offs
- During DST transitions, a "1-day rental" may end at a different clock time than it started
  - Spring forward: 10 AM → 11 AM (1440 minutes later)
  - Fall back: 10 AM → 9 AM (1440 minutes later)
- Some pickup times may become unavailable if the return time falls outside business hours
  - Example: 5 PM pickup + 7 days during DST week = 6 PM return (outside 9-5 availability)

This is the **correct technical behavior** - rental durations should be consistent and measurable.

## Test Changes
Updated test expectations in `spec/services/rental_availability_service_multiday_slots_spec.rb` to:
1. Use `+ duration_mins.minutes` instead of `+ X.days` for expected end times
2. Accept that DST transitions may limit available pickup times
3. Verify all slots use consistent fixed-minute durations

## Verification
Created comprehensive DST test suite in `spec/services/rental_availability_dst_bugfix_spec.rb`:
- ✅ Verifies slot and booking end times match (Cursor bug)
- ✅ Confirms 1440-minute duration stays exactly 1440 minutes across DST (Codex bug)
- ✅ Tests both spring-forward and fall-back DST transitions
- ✅ Validates pricing and duration checks work correctly

## Test Results
- **49 rental-related tests**: All passing ✅
- **3 new DST bug tests**: All passing ✅
- **No regressions detected**

## Conclusion
Both bugs stemmed from the same root cause: inconsistent time calculation methods. The fix ensures all rental duration logic uses fixed-minute calculations, providing consistency across slot display, booking creation, pricing, and validation - even during DST transitions.
