# Past Time Slot Filtering Implementation Summary

## Overview

This implementation adds intelligent filtering of past time slots from the booking interface, ensuring customers cannot book appointments that have already passed. The solution respects business time zones, includes configurable minimum advance booking times, and maintains optimal performance through smart caching.

## Key Features Implemented

### 1. **Core Time Filtering Logic**
- **Location**: `app/services/availability_service.rb`
- **Method**: `filter_past_slots(slots, date, business)`
- **Functionality**: 
  - Filters out time slots that have already passed for the current day
  - Respects business time zones for accurate filtering
  - Applies minimum advance booking time policies
  - Silently removes past slots without user notification

### 2. **Business Time Zone Support**
- Uses `Time.current.in_time_zone(business.time_zone)` for accurate current time calculation
- Maintains UTC storage in database while displaying times in business time zone
- Ensures cross-time zone bookings work correctly
- Fallback to `Time.current` if business time zone is not set

### 3. **Minimum Advance Booking Time Policy**
- **Database**: New `min_advance_mins` field in `booking_policies` table
- **Default**: 0 minutes (no minimum advance time)
- **Configuration**: Business managers can set via settings interface
- **Application**: Filters slots within the advance time window

### 4. **Smart Caching Strategy**
- **Same-day slots**: 5-minute cache TTL with current hour in cache key
- **Future date slots**: 15-minute cache TTL with static cache key
- **Cache invalidation**: Automatic based on time progression
- **Performance**: Maintains responsiveness while ensuring accuracy

### 5. **Real-Time Frontend Filtering (Phase 4, Step 7)**
- **Location**: `app/views/public/tenant_calendar/index.html.erb`, `app/views/business_manager/bookings/available_slots.html.erb`
- **Functionality**:
  - Client-side JavaScript filtering of past slots that have expired since page load
  - Real-time slot count updates every 5 minutes for today's slots
  - Automatic filtering when user returns to tab (visibility API)
  - Complementary to backend filtering for enhanced user experience
- **Features**:
  - Progressive slot hiding as time passes
  - Dynamic slot count updates
  - Console logging for debugging
  - Mobile and desktop view support

## Files Modified

### Core Service Layer
- `app/services/availability_service.rb` - Main filtering logic
- `app/models/booking_policy.rb` - Added validation for min_advance_mins

### Database Changes
- `db/migrate/20250604234331_add_min_advance_mins_to_booking_policies.rb` - New migration
- Added index on `min_advance_mins` for query performance

### User Interface
- `app/views/business_manager/settings/booking_policies/edit.html.erb` - Form field
- `app/views/business_manager/settings/booking_policies/show.html.erb` - Display field
- `app/controllers/business_manager/settings/booking_policies_controller.rb` - Permit parameter

### Testing
- `spec/services/availability_service_spec.rb` - Comprehensive test coverage
- `spec/models/booking_policy_spec.rb` - Validation tests

## Technical Implementation Details

### Time Zone Handling
```ruby
# Business time zone aware current time
current_time = if business.time_zone.present?
                 Time.current.in_time_zone(business.time_zone)
               else
                 Time.current
               end
```

### Cache Key Strategy
```ruby
# Include current hour for same-day slots
time_component = date == Date.current ? Time.current.hour : 'static'
cache_key = ['availability_slots', staff_member.id, date.to_s, service&.id, 
             interval, time_component, staff_member.availability, 
             staff_member.business.booking_policy&.attributes].join('/')
```

### Filtering Logic
```ruby
# Apply minimum advance booking time if policy exists
if policy&.min_advance_mins.present? && policy.min_advance_mins > 0
  cutoff_time = current_time + policy.min_advance_mins.minutes
else
  cutoff_time = current_time
end

filtered_slots = slots.reject { |slot| slot[:start_time] <= cutoff_time }
```

### Real-Time Frontend Filtering (Phase 4, Step 7)
```javascript
// Client-side real-time filtering for same-day slots
function filterPastSlots() {
  const now = new Date();
  const currentDateStr = now.toISOString().split('T')[0];
  const currentTime = now.getTime();
  
  // Filter out slots that have passed since page load
  document.querySelectorAll('.slot-item').forEach(slotElement => {
    const slotDate = slotElement.getAttribute('data-slot-date');
    const slotStartTime = slotElement.getAttribute('data-slot-start');
    
    if (slotDate === currentDateStr && slotStartTime) {
      const slotTime = new Date(slotStartTime).getTime();
      if (slotTime <= currentTime) {
        slotElement.style.display = 'none';
      }
    }
  });
}

// Update every 5 minutes
setInterval(filterPastSlots, 5 * 60 * 1000);
```

## Configuration Options

### Business Policy Settings
- **Minimum Advance Booking Time**: 0-∞ minutes
- **Default**: 0 (no advance requirement)
- **UI Location**: Business Manager → Settings → Booking Policies
- **Field**: "Minimum Advance Booking (Minutes)"

### Cache Configuration
- **Same-day cache TTL**: 5 minutes
- **Future date cache TTL**: 15 minutes
- **Cache key includes**: Current hour for same-day slots

## Testing Coverage

### Unit Tests
- Past time slot filtering for current day
- Future date slot inclusion (no filtering)
- Business time zone respect
- Minimum advance time policy enforcement
- Cache duration verification
- Cache key composition

### Integration Tests
- Booking policy validation
- Form field rendering
- Controller parameter handling

## Performance Considerations

### Optimizations
- **Reduced cache TTL**: Only for same-day slots requiring real-time accuracy
- **Smart cache keys**: Include time component only when necessary
- **Database indexing**: Added index on `min_advance_mins` field
- **Efficient filtering**: Single pass through slots array

### Monitoring
- Debug logging for filtering operations
- Performance metrics via Rails cache monitoring
- Database query optimization through proper indexing

## User Experience

### Behavior
- **Silent filtering**: Past slots are removed without notification
- **Real-time updates**: Same-day slots refresh every 5 minutes
- **Consistent interface**: No UI changes, just fewer available slots
- **Business control**: Configurable minimum advance time

### Edge Cases Handled
- **No business time zone**: Falls back to system time zone
- **Nil policy values**: Treats as no restriction
- **Zero advance time**: Filters only exactly current time
- **Cross-midnight availability**: Properly handles day boundaries

## Deployment Notes

### Database Migration
```bash
rails db:migrate
```

### Cache Warming (Optional)
After deployment, consider warming the cache for popular time slots:
```ruby
# In Rails console
Business.active.each do |business|
  business.staff_members.active.each do |staff|
    staff.services.each do |service|
      AvailabilityService.available_slots(staff, Date.current, service)
    end
  end
end
```

### Monitoring
- Monitor cache hit rates for availability slots
- Watch for increased database queries during peak booking times
- Track booking conversion rates to ensure filtering doesn't negatively impact business

## Future Enhancements

### Potential Improvements
1. **Real-time WebSocket updates**: Push slot availability changes to connected clients
2. **Predictive caching**: Pre-warm cache for likely-to-be-requested slots
3. **Business hours integration**: Respect business operating hours for filtering
4. **Holiday handling**: Integrate with business holiday calendars
5. **Staff-specific policies**: Allow different advance times per staff member

### API Considerations
If exposing booking availability via API:
- Include time zone information in responses
- Document filtering behavior
- Provide policy information in API responses
- Consider rate limiting for availability checks

## Conclusion

This implementation provides a robust, performant solution for filtering past time slots while maintaining the existing architecture and user experience. The solution properly handles time zones, includes business-configurable policies, and ensures optimal performance through intelligent caching strategies.

The implementation is backward-compatible, thoroughly tested, and ready for production deployment. 