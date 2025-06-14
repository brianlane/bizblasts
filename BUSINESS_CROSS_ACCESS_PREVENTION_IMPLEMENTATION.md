# Business Cross-Access Prevention Implementation

## Overview

This implementation prevents business users (managers and staff) from booking services or purchasing products from businesses other than their own. When a business user attempts to access another business's booking or cart functionality, they are redirected with a clear message instructing them to sign out and proceed as a guest.

## Implementation Components

### 1. BusinessAccessGuard Service (`app/services/business_access_guard.rb`)

A service class that encapsulates the logic for:
- Detecting when business users are accessing other businesses
- Providing appropriate redirect paths
- Clearing cross-business cart items
- Logging security events

**Key Methods:**
- `should_block_access?` - Determines if access should be blocked
- `block_message` - Returns the flash message
- `clear_cross_business_cart!` - Clears cart when blocking access
- `redirect_path_for_blocked_user` - Generates redirect URL to user's own business

### 2. BusinessAccessProtection Concern (`app/controllers/concerns/business_access_protection.rb`)

A controller concern that:
- Runs before actions on protected controllers
- Uses BusinessAccessGuard to check access
- Handles redirects and flash messages
- Logs security events

### 3. Protected Controllers

The following controllers now include the `BusinessAccessProtection` concern:

- `Public::BookingController` - Booking creation
- `LineItemsController` - Cart item management
- `CartsController` - Cart viewing
- `Public::OrdersController` - Order creation
- `ProductsController` - Product browsing

### 4. User Access Rules

**Business Users (Manager/Staff):**
- ✅ Can access their own business's booking/cart functionality
- ❌ Cannot access other businesses' booking/cart functionality
- 🔄 Redirected to their own business dashboard when blocked

**Client Users:**
- ✅ Can access any business's booking/cart functionality
- 🎯 This supports the multi-business client model

**Guest Users:**
- ✅ Can access any business's booking/cart functionality
- 🌐 No restrictions for unauthenticated users

## Security Features

### 1. Cart Clearing
When a business user is blocked from accessing another business, any cart items are automatically cleared to prevent data leakage.

### 2. Security Logging
All blocked access attempts are logged with:
- User ID and role
- Source business ID
- Target business ID
- IP address
- Controller and action attempted

### 3. Cross-Environment Support
The redirect URLs are generated appropriately for:
- Development (lvh.me with port)
- Production (HTTPS with proper domains)
- Both subdomain and custom domain configurations

## Flash Message

When access is blocked, users see:
> "You must sign out and proceed as a guest to book services or purchase items from other businesses."

## Testing

### Unit Tests (`spec/services/business_access_guard_spec.rb`)
Comprehensive tests covering:
- All user role scenarios
- Environment-specific redirect URLs
- Cart clearing functionality
- Security logging

### System Tests (`spec/system/business_cross_access_prevention_spec.rb`)
End-to-end tests verifying:
- Manager and staff are blocked from other businesses
- Clients and guests can access any business
- Proper redirects and flash messages
- Cart clearing behavior

## Implementation Checklist

- [x] Create BusinessAccessGuard service
- [x] Create BusinessAccessProtection concern
- [x] Update Public::BookingController
- [x] Update LineItemsController
- [x] Update CartsController
- [x] Update Public::OrdersController
- [x] Update ProductsController
- [x] Create comprehensive unit tests
- [x] Create system integration tests
- [x] Document implementation

## Usage

The protection is automatically applied to controllers that include the `BusinessAccessProtection` concern. No additional configuration is required.

### Adding Protection to New Controllers

To protect additional controllers:

```ruby
class YourController < ApplicationController
  include BusinessAccessProtection
  
  # Your controller logic
end
```

### Customizing Behavior

The BusinessAccessGuard service can be extended or customized by:

1. Modifying the `should_block_access?` logic
2. Customizing the flash message in `block_message`
3. Adjusting redirect logic in `redirect_path_for_blocked_user`

## Security Considerations

1. **User Role Verification**: The system relies on the user's role and business_id associations
2. **Tenant Context**: Proper tenant setting is required for the protection to work
3. **Session Security**: Cart clearing prevents cross-tenant data exposure
4. **Logging**: Security events are logged for monitoring and audit trails

## Performance Impact

- Minimal performance impact as the check only runs for authenticated users on tenant subdomains
- Guard object creation is lightweight
- Database queries are avoided when possible (uses in-memory user data)

## Monitoring

Monitor the security logs for:
- Unusual patterns of blocked access attempts
- Users attempting to access multiple different businesses
- Potential security issues or user confusion

Search for log entries containing: `[SECURITY] Business user ... attempted to access`

## Future Enhancements

Potential improvements:
1. More granular permissions (e.g., allow staff to view but not book)
2. Notification system for business owners about blocked access attempts
3. Rate limiting for repeated cross-business access attempts
4. Admin override functionality for support scenarios 