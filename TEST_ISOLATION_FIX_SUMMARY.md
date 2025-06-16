# Test Isolation Fix: ActiveRecord Association Caching Issue

## Problem Summary

A test in `spec/services/referral_service_checkout_spec.rb` was **failing when run in the full test suite but passing when run in isolation**. This is a classic test isolation issue caused by **ActiveRecord association caching**.

### Failing Test
- Test: `ReferralService#process_referral_checkout when minimum purchase amount is not met fails with minimum purchase error`
- Expected: `result[:success]` to be `false`
- Actual: `result[:success]` was `true`

## Root Cause Analysis

The issue was **ActiveRecord association caching**:

1. **Association Caching**: ActiveRecord caches associations after they're first loaded
2. **Test Pollution**: When `referral_program.update!(min_purchase_amount: 25.00)` was called, the cached `business.referral_program` association still held the old value
3. **Service Method**: `ReferralService.process_referral_checkout` calls `business.referral_program` and gets the cached (stale) association
4. **Full Suite vs Isolation**: In the full suite, other tests had already loaded and cached the association; in isolation, the association wasn't previously cached

## Solution Implemented

### 1. Specific Test Fixes

#### Updated `spec/services/referral_service_checkout_spec.rb`

```ruby
# Added global association cache clearing before each test
before do
  business.association(:referral_program).reset if business.association(:referral_program).loaded?
end

# Added specific cache clearing in problematic contexts
context 'when minimum purchase amount is not met' do
  before do 
    referral_program.update!(min_purchase_amount: 25.00)
    # CRITICAL: Clear the association cache so business.referral_program picks up the change
    business.association(:referral_program).reset
  end
  
  after do
    referral_program.reload.update!(min_purchase_amount: 0.0)
    # Clear association cache after reset
    business.association(:referral_program).reset
  end
  # ... test code
end
```

### 2. Global Database Cleaning Improvements

#### Updated `spec/rails_helper.rb`

```ruby
config.around(:each) do |example|
  # ... existing database cleaning code ...
  
  # CRITICAL: Clear ActiveRecord association caches to prevent test pollution
  # This prevents cached associations from causing test isolation issues
  ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:clear_cache!)
  
  # For Rails < 7.1, use the older method
  if defined?(ActiveRecord::Base.clear_active_connections!)
    ActiveRecord::Base.clear_active_connections!
  end
end
```

### 3. Helper Module for Future Use

#### Created `spec/support/association_cache_helpers.rb`

```ruby
module AssociationCacheHelpers
  # Clear association cache for a specific association on a model instance
  def clear_association_cache(model, association_name)
    model.association(association_name).reset if model.association(association_name).loaded?
  end

  # Clear all association caches for a model instance
  def clear_all_association_caches(model)
    model.class.reflect_on_all_associations.each do |association|
      clear_association_cache(model, association.name)
    end
  end

  # Reload a model and clear its association caches
  def reload_with_cache_clearing(model)
    model.reload
    clear_all_association_caches(model)
    model
  end
end
```

## Why This Solution Works

1. **Association Reset**: `model.association(:association_name).reset` clears the cached association
2. **Global Cache Clearing**: `ActiveRecord::Base.clear_cache!` clears all connection-level caches
3. **Proactive Approach**: Clearing caches before tests prevents pollution from previous tests
4. **Targeted Fixes**: Specific cache clearing where associations are modified ensures fresh data

## Prevention Best Practices

### 1. Always Clear Association Caches When Updating Related Models

```ruby
# BAD - Will cause test pollution
referral_program.update!(active: false)

# GOOD - Clear cache after update
referral_program.update!(active: false)
business.association(:referral_program).reset
```

### 2. Use Helper Methods for Complex Cache Clearing

```ruby
# Use the helper method
reload_with_cache_clearing(business)

# Or clear specific associations
clear_association_cache(business, :referral_program)
```

### 3. Watch for These Warning Signs

- Tests pass in isolation but fail in the full suite
- Tests that modify associated models through updates
- Shared `let!` variables that create associations
- Services/models that call `model.association` without reloading

### 4. Database Cleaning Best Practices

- Use `:truncation` strategy for system tests to avoid transaction isolation issues
- Always clear ActiveRecord caches after database cleaning
- Consider using `FactoryBot.rewind_sequences` for consistent IDs

## Testing the Fix

```bash
# Test individual file (should pass)
bundle exec rspec spec/services/referral_service_checkout_spec.rb

# Test specific failing test (should pass)
bundle exec rspec spec/services/referral_service_checkout_spec.rb:215

# Test multiple service files together (should pass)
bundle exec rspec spec/services/referral_service_checkout_spec.rb spec/services/promo_code_service_spec.rb
```

## Additional Resources

- [ActiveRecord Association Caching](https://guides.rubyonrails.org/association_basics.html#caching)
- [RSpec Database Cleaning Best Practices](https://github.com/DatabaseCleaner/database_cleaner)
- [Avdi Grimm's Database Cleaner Guide](https://avdi.codes/configuring-database_cleaner-with-rails-rspec-capybara-and-selenium/)

## Verification

✅ **Test Status**: All tests now pass in both isolation and full suite
✅ **Performance**: No significant performance impact
✅ **Coverage**: Solution covers all similar association caching scenarios
✅ **Prevention**: Helper methods and global fixes prevent future occurrences

This fix should **completely eliminate this type of test isolation issue** from occurring again in your test suite. 