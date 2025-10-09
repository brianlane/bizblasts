# Cursor Bug Fixes - Twilio & CustomerLinker

## Summary
Fixed **five critical bugs** identified by Cursor in the Twilio webhook and CustomerLinker code that could lead to data integrity issues, security vulnerabilities, runtime errors, database portability problems, and performance issues.

---

## Bug 1: Phone Conflict Checks Failed to Trigger
**File:** `app/services/customer_linker.rb:333-336`

### Problem
The `phone_duplicate_resolution_skipped` flag in `resolve_phone_conflicts_for_user` was initialized to `false` but never set to `true`, causing critical security checks in `handle_unlinked_customer_by_email` (line 390) and `check_final_phone_conflicts` (line 463) to never trigger. This could allow linking or creating customers with conflicting phone numbers.

### Root Cause
When phone duplicates were found with the canonical customer already linked to a different user, the code would merge duplicates but failed to set the `phone_duplicate_resolution_skipped` flag that would prevent the current user from linking to that phone number.

### Fix
**Location:** `customer_linker.rb:335`

```ruby
# BEFORE:
# Don't set phone_duplicate_resolution_skipped since we successfully resolved duplicates
# Only set conflicting_user_id to indicate the canonical customer is linked elsewhere
conflicting_user_id = canonical_customer.user_id

# AFTER:
# CRITICAL: Set phone_duplicate_resolution_skipped to prevent linking/creating customers with conflicting phones
# This ensures security checks in handle_unlinked_customer_by_email and check_final_phone_conflicts trigger
phone_duplicate_resolution_skipped = true
conflicting_user_id = canonical_customer.user_id
```

### Impact
- **Security:** Prevents phone number sharing across different user accounts
- **Data Integrity:** Ensures phone number uniqueness per user is enforced
- **Behavior Change:** Now raises `PhoneConflictError` when attempting to link a phone number already associated with a different user

---

## Bug 2: Class Method Called on Instance
**File:** `app/controllers/webhooks/twilio_controller.rb:690`

### Problem
The `find_customers_by_phone` method was creating a new `CustomerLinker` instance and calling an instance method, which was inconsistent with the pattern used elsewhere in the controller (line 694 uses class methods). This created unnecessary object instantiation and was inconsistent with the codebase patterns.

### Root Cause
Mixed usage of instance methods and class methods for the same operation, creating confusion and potential for errors.

### Fix
**Location:** `twilio_controller.rb:691`

```ruby
# BEFORE:
# Business-scoped search using instance method
customers_array = CustomerLinker.new(business).find_customers_by_phone_public(phone_number)

# AFTER:
# Business-scoped search using class method for consistency
customers_array = CustomerLinker.find_customers_by_phone_public(phone_number, business)
```

### Impact
- **Consistency:** All CustomerLinker phone lookups now use class methods consistently
- **Performance:** Eliminates unnecessary object instantiation
- **Maintainability:** Clearer API - class methods for lookups, instance methods for operations on business data

---

## Bug 3: Mocking Mismatch in Tests
**File:** `spec/requests/webhooks/twilio_inbound_spec.rb:261-263`

### Problem
Test mocks didn't accurately reflect the actual method definitions. The test was mocking an instance method when the controller now uses class methods.

### Fix
**Location:** `twilio_inbound_spec.rb:263`

```ruby
# BEFORE:
# Mock the phone lookup method that's also called during opt-in processing
allow(linker_instance).to receive(:find_customers_by_phone_public).with(user_without_customer.phone).and_return([new_customer])

# AFTER:
# Mock the CLASS METHOD for phone lookup (used by TwilioController#find_customers_by_phone)
# This accurately reflects the controller's implementation which uses class methods for consistency
allow(CustomerLinker).to receive(:find_customers_by_phone_public).with(user_without_customer.phone, business).and_return([new_customer])
```

### Impact
- **Test Accuracy:** Tests now correctly reflect the actual implementation
- **Maintainability:** Prevents false positives and ensures tests catch real issues
- **Documentation:** Tests serve as accurate documentation of the API

---

## Bug 4: Database Portability Issue with REGEXP_REPLACE
**File:** `app/services/customer_linker.rb:179`

### Problem
The `resolve_all_phone_duplicates` method used PostgreSQL-specific syntax `REGEXP_REPLACE(phone, '[^0-9]', '', 'g')` with the 'g' flag in its WHERE clause. This would cause runtime errors on MySQL, SQLite, or other databases, breaking database portability.

### Root Cause
Attempting to filter phone numbers by digit count at the database level using PostgreSQL-specific regex functions instead of using database-agnostic approaches.

### Fix
**Location:** `customer_linker.rb:177-186`

```ruby
# BEFORE:
@business.tenant_customers
         .where.not(phone: [nil, ''])
         .where("LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '', 'g')) >= ?", 7)  # PostgreSQL-specific!
         .find_in_batches(batch_size: 1000) do |batch|

# AFTER:
@business.tenant_customers
         .where.not(phone: [nil, ''])
         .find_in_batches(batch_size: 1000) do |batch|
  # Group this batch by normalized phone
  # Ruby-level normalization handles validity checks (length >= 7) for database portability
  batch_groups = batch.group_by { |customer|
    normalized = normalize_phone(customer.phone)
    normalized.presence # Skip customers where normalization fails (nil for invalid phones)
  }.reject { |normalized_phone, customers| normalized_phone.nil? }
```

### Impact
- **Database Portability:** Code now works on PostgreSQL, MySQL, SQLite, and any ActiveRecord-supported database
- **Maintainability:** Reduces database-specific code and centralizes phone validation in Ruby
- **Performance:** Minimal impact - validation already happened in Ruby during batch processing
- **Reliability:** Prevents runtime errors when switching databases or running tests with different database engines

---

## Bug 5: Guest Customer Method Inefficient Phone Lookup and API Contract
**File:** `app/services/customer_linker.rb:82`

### Problem
The `find_or_create_guest_customer` method had two issues:
1. **Performance Issue (Line 82):** Used inefficient Ruby enumeration (`phone_customers.find { |c| c.user_id.present? }`) instead of SQL filtering
2. **API Contract:** Method name implies "find or create" behavior but raises `GuestConflictError` exceptions

### Root Cause
**Issue 1:** The phone conflict check used `.find { }` on an ActiveRecord::Relation, which implicitly converts the Relation to an Array and iterates in Ruby instead of filtering in SQL. This loads all matching phone customers into memory unnecessarily.

**Issue 2:** Security checks were added to prevent guests from using credentials belonging to registered users, but this changed the method's contract from "always returns a customer" to "returns customer OR raises exception." While this is intentional security behavior, it was not documented.

### Fix

**Issue 1 Fix - Line 83:**
```ruby
# BEFORE:
phone_customers = find_customers_by_phone(customer_attributes[:phone])
linked_phone_customer = phone_customers.find { |c| c.user_id.present? }

# AFTER:
phone_customers = find_customers_by_phone(customer_attributes[:phone])
# Use ActiveRecord to filter in SQL instead of loading all customers and filtering in Ruby
linked_phone_customer = phone_customers.where.not(user_id: nil).first
```

**Issue 2 Fix - Added Documentation (Lines 40-50):**
```ruby
# Find or create customer for guest checkout (no user account)
#
# Returns the guest customer if found or created successfully.
#
# @raise [GuestConflictError] if the email or phone is already linked to a registered user account
#   This security check prevents guests from using credentials belonging to registered users.
#   Callers should handle this exception and prompt the user to sign in instead.
#
# @param email [String] The email address for the guest customer
# @param customer_attributes [Hash] Additional attributes (first_name, last_name, phone, phone_opt_in)
# @return [TenantCustomer] The guest customer record
def find_or_create_guest_customer(email, customer_attributes = {})
```

### Impact

**Issue 1 Impact:**
- **Performance:** Phone lookups now use SQL WHERE clause instead of loading and filtering in Ruby
- **Efficiency:** Reduces memory usage by filtering in the database layer
- **Database Load:** Fewer rows transferred from database to application
- **Maintainability:** More idiomatic ActiveRecord usage

**Issue 2 Impact:**
- **Documentation:** API contract is now clearly documented with `@raise` annotations
- **Caller Awareness:** All callers already handle `GuestConflictError` (verified in controllers)
- **Security Maintained:** Security checks remain in place to prevent credential reuse
- **No Breaking Changes:** Existing code continues to work as callers already handle exceptions

### Security Implications
The `GuestConflictError` exceptions are **intentional security features**, not bugs:
- Prevents guests from checking out with emails belonging to registered users
- Prevents guests from using phone numbers belonging to registered users
- Forces users to sign in if they already have an account
- All callers (BookingController, OrdersController, SubscriptionsController) properly handle these exceptions

---

## Additional Changes

### New Test Files Created

1. **`spec/services/customer_linker_phone_conflicts_spec.rb`**
   - Comprehensive tests for phone conflict detection
   - Validates the `phone_duplicate_resolution_skipped` flag behavior
   - Tests all code paths for phone duplicate scenarios
   - Verifies CustomerLinker method signatures (instance vs class methods)
   - 15 examples, all passing

2. **`spec/controllers/webhooks/twilio_controller_method_usage_spec.rb`**
   - Validates correct usage of CustomerLinker class methods
   - Tests integration with customer linking
   - Ensures no `NoMethodError` from incorrect method calls
   - 12 examples, all passing

3. **`spec/services/customer_linker_guest_customer_spec.rb`**
   - Comprehensive tests for `find_or_create_guest_customer` method
   - Tests efficient SQL filtering for phone lookups (Bug 5 Issue 1)
   - Tests `GuestConflictError` exception handling (Bug 5 Issue 2)
   - Tests normal "find or create" behavior without conflicts
   - Tests edge cases and validation
   - 18 examples, all passing

### Updated Test Files

4. **`spec/services/customer_linker_spec.rb`**
   - Updated test expectations to match the new secure behavior
   - Changed test "merges duplicates but preserves existing user linkage when canonical customer is linked to different user" to expect `PhoneConflictError`
   - This reflects the CORRECT behavior after the bug fix

---

## Test Results

All tests passing:
- ✅ `customer_linker_phone_conflicts_spec.rb`: 15 examples, 0 failures
- ✅ `twilio_controller_method_usage_spec.rb`: 12 examples, 0 failures
- ✅ `customer_linker_guest_customer_spec.rb`: 18 examples, 0 failures
- ✅ `twilio_inbound_spec.rb`: 17 examples, 0 failures
- ✅ `customer_linker_spec.rb`: 34 examples, 0 failures

**Total:** 96 examples, 0 failures

---

## Files Modified

### Production Code
1. `app/services/customer_linker.rb` (Bugs 1, 4, 5)
   - Line 335: Bug 1 fix (set `phone_duplicate_resolution_skipped` flag)
   - Lines 177-186: Bug 4 fix (removed PostgreSQL-specific REGEXP_REPLACE)
   - Line 83: Bug 5 Issue 1 fix (efficient SQL filtering)
   - Lines 40-50: Bug 5 Issue 2 fix (added documentation)
2. `app/controllers/webhooks/twilio_controller.rb` (Bug 2)
   - Line 691: Changed from instance method to class method

### Test Code
3. `spec/requests/webhooks/twilio_inbound_spec.rb` (Bug 3)
   - Line 263: Updated mock to use class method
4. `spec/services/customer_linker_spec.rb` (Bug 1)
   - Updated test expectations to expect `PhoneConflictError`
5. `spec/services/customer_linker_phone_conflicts_spec.rb` (NEW - 263 lines)
   - Tests for Bugs 1 and 4
6. `spec/controllers/webhooks/twilio_controller_method_usage_spec.rb` (NEW - 156 lines)
   - Tests for Bug 2
7. `spec/services/customer_linker_guest_customer_spec.rb` (NEW - 305 lines)
   - Tests for Bug 5

---

## Security Implications

### Before Fixes
- ⚠️ Users could share phone numbers across accounts (data privacy violation)
- ⚠️ Phone uniqueness constraints were not enforced
- ⚠️ SMS notifications could be sent to wrong recipients

### After Fixes
- ✅ Phone numbers are strictly unique per user within a business
- ✅ `PhoneConflictError` is raised when attempting to use a phone number linked to a different user
- ✅ Clear error messages guide users to resolve conflicts
- ✅ Data integrity maintained while merging duplicates

---

## Recommended Next Steps

1. **Deploy to staging** - Verify the fixes work in a production-like environment
2. **Monitor error logs** - Watch for `PhoneConflictError` occurrences (they indicate the fix is working)
3. **Review edge cases** - Check for any customer support tickets related to phone number conflicts
4. **Documentation** - Update API documentation to reflect the phone uniqueness constraint

---

## Notes

- All fixes are backward compatible with existing data
- The fixes are defensive and prevent future bugs
- Comprehensive test coverage ensures the bugs won't regress
- Clear error messages help users understand and resolve conflicts
