# Encryption Cleanup Summary

## Rails 8.0 Encryption Pattern ✅

Rails 8.0 stores encrypted data **in the same column** as the attribute name, not in a `*_ciphertext` suffixed column.

```ruby
# Rails 8.0 Convention
encrypts :phone, deterministic: true
# Stores encrypted data in 'phone' column (text type)
```

## Current State (Cleaned Up)

### SmsMessage
- **Column**: `phone_number` (text) - stores encrypted JSON
- **Model**: `encrypts :phone_number, deterministic: true`
- **Index**: `index_sms_messages_on_phone_number` on `[:phone_number]`
- **Scope**: `for_phone` uses `where(phone_number: normalized)`
- **✅ No legacy `*_ciphertext` columns**

### TenantCustomer  
- **Column**: `phone` (string) - stores encrypted JSON
- **Model**: `encrypts :phone, deterministic: true`
- **Index**: `index_tenant_customers_on_business_phone_for_users` on `[:business_id, :phone]` 
  - Unique constraint with `WHERE user_id IS NOT NULL`
  - Allows guests (user_id IS NULL) to share phone numbers
- **Scopes**: 
  - `for_phone` uses `where(phone: normalized)`
  - `for_phone_set` uses `where(phone: normalized_set)`
  - `with_phone` uses `where.not(phone: nil)`
- **✅ No legacy `*_ciphertext` columns**

### User
- **Column**: `phone` - stores encrypted JSON  
- **Model**: `encrypts :phone, deterministic: true`
- **✅ No legacy `*_ciphertext` columns**

## Key Features

### 1. Deterministic Encryption
All phone fields use `deterministic: true`, enabling:
- Direct equality queries: `where(phone: "+15551234567")`
- Scope-based lookups: `TenantCustomer.for_phone(phone_number)`
- Unique constraints on encrypted data

### 2. Phone Normalization
`PhoneNormalizer` ensures consistency:
- Returns `nil` for invalid/blank input (prevents junk writes)
- Normalizes to E.164 format: `+15551234567`
- Minimum 7 digits required
- All scopes and validations use normalized values

### 3. Security Configuration
**Test Environment** (`config/environments/test.rb`):
```ruby
config.active_record.encryption.support_unencrypted_data = false
```
- ✅ CI will fail if any code relies on plaintext
- ✅ Forces all data to be encrypted

### 4. Verification Methods

#### Check Raw Encrypted Value
```ruby
sms = SmsMessage.last
sms.read_attribute_before_type_cast(:phone_number)
# => {"p":"b8yTdh5bTcssVhJn","h":{"iv":"...","at":"..."}}
```

#### Check Decrypted Value
```ruby
sms.phone_number
# => "+15551234567"
```

#### Verify Encryption is Configured
```ruby
SmsMessage.encrypted_attributes
# => [:phone_number]

TenantCustomer.encrypted_attributes  
# => [:phone]
```

## Migrations Applied

1. **`20251024214607_add_phone_number_back_to_sms_messages.rb`**
   - Added `phone_number` column to `sms_messages`
   - Copied data from legacy `phone_number_ciphertext`
   - Added index on `phone_number`

2. **`20251024215419_remove_legacy_phone_number_ciphertext_from_sms_messages.rb`**
   - Removed legacy `phone_number_ciphertext` column
   - Removed legacy index

3. **`20251024221011_remove_legacy_phone_ciphertext_columns.rb`**
   - Removed legacy `phone_ciphertext` from `tenant_customers`
   - Removed legacy `phone_ciphertext` from `users`
   - Removed all associated indexes

4. **`20251024221352_add_unique_phone_index_for_linked_users.rb`**
   - Added correct unique index on `[:business_id, :phone]`
   - Partial index with `WHERE user_id IS NOT NULL`

## Test Coverage

✅ **spec/models/sms_message_encryption_spec.rb**
- Verifies encryption is configured
- Confirms encrypted JSON storage
- Tests automatic encryption/decryption
- Validates deterministic querying
- Ensures no `*_ciphertext` columns exist

## Legacy References

The only remaining `*_ciphertext` references are:
1. **Historical migrations** (cannot be changed)
2. **Documentation** (this file, explaining the cleanup)
3. **Test specs** (verifying the pattern)

**No active application code** references `*_ciphertext` columns.

## Consistency Checks

### Status Update Methods
All `SmsMessage` status methods use `update_columns` consistently:
- `mark_as_sent!` - bypasses callbacks, updates `updated_at`
- `mark_as_delivered!` - bypasses callbacks, updates `updated_at`
- `mark_as_failed!` - bypasses callbacks, updates `updated_at`

### Phone Validation
- `SmsService.valid_phone_number?` delegates to `PhoneNormalizer`
- All models use `PhoneNormalizer` in before_validation callbacks
- Consistent validation across `SmsMessage`, `TenantCustomer`, and `User`

## Summary

The encryption implementation is now:
✅ **Consistent** - All models use `encrypts :phone` (same column pattern)  
✅ **Secure** - Encrypted JSON storage, no plaintext in database  
✅ **Queryable** - Deterministic encryption enables `where` queries  
✅ **Clean** - No legacy `*_ciphertext` columns or references  
✅ **Validated** - `support_unencrypted_data = false` enforces encryption  
✅ **Tested** - 255+ tests pass, including encryption-specific tests

