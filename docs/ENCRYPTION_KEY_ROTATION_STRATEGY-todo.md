# Encryption Key Rotation Strategy & Data Recovery Plan

**Document Version:** 1.0
**Last Updated:** October 29, 2025
**Status:** Long-Term Strategy (Hotfixes Deployed)
**Owner:** Engineering Team

---

## Executive Summary

### The Problem
Production bookings are failing due to `ActiveRecord::Encryption::Errors::Decryption` exceptions when accessing encrypted phone data. This occurs when encryption keys have been rotated or changed, making previously encrypted data unreadable with current keys.

### Current State (Hotfixes)
We have implemented **5 tactical hotfix commits** that provide immediate production stability by gracefully handling decryption errors and allowing booking flows to continue. These hotfixes are **safe to deploy** as they introduce no breaking changes and are purely defensive.

**Hotfix Commits:**
1. `5885ef7` - Production hotfix: Handle decryption errors in CustomerLinker
2. `8888669` - Add rake task to clear corrupted phone data
3. `510d057` - Fix undefined variable in conditional code path
4. `0caffda` - Fix decryption errors in log statements
5. `896973a` - Fix inconsistent phone handling in sync method

### What Hotfixes Solve
✅ **Immediate Production Stability** - Bookings work again
✅ **Graceful Degradation** - CustomerLinker continues without phone-based matching
✅ **Data Cleanup Tools** - Rake tasks to identify and clear corrupted records
✅ **Code Quality** - Fixed 4 bugs identified by automated code review
✅ **No Breaking Changes** - Defensive error handling only

### What Hotfixes Don't Solve
❌ **Root Cause** - Encryption key mismatches remain
❌ **Data Loss** - Phone numbers returned as nil (lost)
❌ **Incomplete Coverage** - SMS delivery and calendar sync still vulnerable
❌ **Future Key Rotation** - Will break again if keys change
❌ **Data Recovery** - Cannot recover encrypted data with old keys

### Long-Term Strategy
This document outlines a **4-phase implementation plan** using Rails Active Record Encryption's `previous:` keys feature to:
- ✅ **Recover ALL existing encrypted data** that was encrypted with old keys
- ✅ **Prevent future key rotation issues** across all encrypted fields
- ✅ **Gradually re-encrypt data** with current keys
- ✅ **Track encryption key versions** for proper key management

---

## Table of Contents

1. [Background & Root Cause Analysis](#background--root-cause-analysis)
2. [Complete Encryption Inventory](#complete-encryption-inventory)
3. [Current Hotfix Implementation](#current-hotfix-implementation)
4. [Long-Term Solution Architecture](#long-term-solution-architecture)
5. [Implementation Roadmap](#implementation-roadmap)
6. [Technical Implementation Details](#technical-implementation-details)
7. [Comparison: Hotfixes vs Long-Term Solution](#comparison-hotfixes-vs-long-term-solution)
8. [Decision Log](#decision-log)
9. [Technical References](#technical-references)

---

## Background & Root Cause Analysis

### How Active Record Encryption Works

Rails 7+ includes native Active Record Encryption that provides transparent encryption/decryption of model attributes. It supports two modes:

**1. Deterministic Encryption**
- Encrypts the same plaintext to the same ciphertext consistently
- Allows database queries on encrypted fields (e.g., `User.where(phone: "+1234567890")`)
- Uses a dedicated `deterministic_key` from configuration
- **Does NOT support Rails' built-in global key rotation** (by design)
- Used for: `User.phone`, `TenantCustomer.phone`, `SmsMessage.phone_number`

**2. Non-Deterministic Encryption**
- Encrypts the same plaintext to different ciphertext each time (includes random IV)
- Cannot query encrypted fields directly
- Uses the `primary_key` from configuration
- **Supports Rails' built-in global key rotation** with `previous:` parameter
- Used for: `CalendarConnection.access_token`, `CalendarConnection.refresh_token`, `CalendarConnection.caldav_password`

### Why Key Rotation Causes Decryption Failures

When encryption keys are rotated (changed in `config/credentials.yml.enc` or environment variables), Rails Active Record Encryption cannot decrypt data that was encrypted with the old keys. This causes:

```ruby
# Old key used to encrypt
user.phone = "+1234567890"  # Encrypted with KEY_v1
user.save!

# Keys rotated (KEY_v1 → KEY_v2)
# Now trying to read:
user.phone  # Raises ActiveRecord::Encryption::Errors::Decryption
```

**The Problem:** Rails has no fallback mechanism by default. If the current key doesn't match the key used for encryption, decryption fails immediately.

**The Solution:** Rails provides the `previous:` parameter to configure fallback keys. Rails will:
1. Try decrypting with current key
2. If that fails, try each key in `previous:` array
3. When record is saved, re-encrypt with current key automatically

### Deterministic vs Non-Deterministic Key Rotation

This is a **critical distinction**:

**Deterministic Fields (Phone Numbers)**
- **Global key rotation NOT supported** in Rails
- Must use **attribute-level `previous:` configuration** for each field
- Example:
  ```ruby
  encrypts :phone,
    deterministic: true,
    previous: [{
      deterministic_key: ENV['OLD_DETERMINISTIC_KEY']
    }]
  ```

**Non-Deterministic Fields (Tokens, Passwords)**
- **Global key rotation IS supported** in Rails
- Configure **once in initializer**, applies to all non-deterministic fields
- Example:
  ```ruby
  # config/initializers/active_record_encryption.rb
  config.active_record.encryption.previous = [{
    primary_key: ENV['OLD_PRIMARY_KEY'],
    key_derivation_salt: ENV['OLD_KEY_DERIVATION_SALT']
  }]
  ```

### Password Handling (Important Context)

The application uses **two different security models** for password data:

**1. User Authentication Passwords (Devise + bcrypt)**
- Field: `User.encrypted_password`
- Uses **bcrypt hashing** (one-way transformation)
- **NOT** Active Record Encryption
- Not affected by encryption key rotation
- Passwords cannot be decrypted (by design)

**2. CalDAV Integration Passwords (Active Record Encryption)**
- Field: `CalendarConnection.caldav_password`
- Uses **Active Record Encryption** (reversible)
- **IS** affected by encryption key rotation
- Must be decrypted to authenticate with CalDAV servers
- Vulnerable to key rotation issues

---

## Complete Encryption Inventory

The application encrypts **6 attributes** across 4 models:

| Model | Field | Encryption Type | Current Protection | Vulnerability | Impact if Keys Rotate |
|-------|-------|----------------|-------------------|--------------|---------------------|
| **User** | `phone` | Deterministic | 🟡 **Partial** - Only `normalize_phone_number` callback has error handling | 🟡 MEDIUM | Booking failures, phone normalization fails, customer linking degrades |
| **TenantCustomer** | `phone` | Deterministic | 🟢 **Full** - CustomerLinker uses `safe_phone_access()` method | 🟢 LOW | Graceful degradation, booking continues without phone matching |
| **SmsMessage** | `phone_number` | Deterministic | 🔴 **None** - Direct access in `deliver` method and query scopes | 🔴 HIGH | SMS delivery crashes, historical message queries fail |
| **CalendarConnection** | `access_token` | Non-deterministic | 🔴 **None** - Direct access in Google/OAuth services | 🔴 HIGH | Calendar sync crashes, OAuth refresh fails |
| **CalendarConnection** | `refresh_token` | Non-deterministic | 🔴 **None** - Direct access in OAuth token refresh | 🔴 HIGH | Cannot refresh expired access tokens |
| **CalendarConnection** | `caldav_password` | Non-deterministic | 🔴 **None** - Direct access in CalDAV service initialization | 🔴 CRITICAL | CalDAV authentication crashes, calendar sync stops |

### Vulnerability Levels Explained

- 🟢 **LOW**: Full error handling, graceful degradation, no user impact
- 🟡 **MEDIUM**: Partial protection, some user-facing failures possible
- 🔴 **HIGH**: No protection, critical feature failures, requires immediate attention
- 🔴 **CRITICAL**: No protection, complete service outage, security implications

### Locations of Direct Access (Vulnerable Code)

**User.phone**
- `app/models/user.rb:806-831` - `normalize_phone_number` callback (HAS error handling)
- `app/services/customer_linker.rb` - Multiple locations (NOW PROTECTED by hotfix)

**TenantCustomer.phone**
- `app/services/customer_linker.rb` - Multiple locations (NOW PROTECTED by hotfix)

**SmsMessage.phone_number**
- `app/models/sms_message.rb:68` - `deliver` method (NO protection)
- `app/models/sms_message.rb:38-44` - `for_phone` scope (NO protection)

**CalendarConnection.access_token**
- `app/services/calendar/google_service.rb:172` - Token refresh (NO protection)

**CalendarConnection.refresh_token**
- `app/services/calendar/oauth_handler.rb:223` - Token request (NO protection)

**CalendarConnection.caldav_password**
- `app/services/calendar/caldav_service.rb:17` - Service initialization (NO protection)
- `app/controllers/business_manager/settings/calendar_integrations_controller.rb:104` - Password display (NO protection)

---

## Current Hotfix Implementation

### Commit 1: Production Hotfix - Handle Decryption Errors (`5885ef7`)

**File:** `app/services/customer_linker.rb`

**Changes:**
1. Added `safe_phone_access()` method to wrap phone field access with error handling
2. Wrapped entire `resolve_phone_conflicts_for_user()` call with rescue block
3. Updated all direct phone accesses to use safe accessor

**Code Example:**
```ruby
def safe_phone_access(record)
  return nil if record.nil?

  begin
    record.phone
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    record_type = record.class.name
    record_id = record.id

    SecureLogger.error "[CUSTOMER_LINKER] Decryption error for #{record_type} #{record_id}"
    SecureLogger.error "[CUSTOMER_LINKER] This #{record_type}'s phone data was encrypted with different keys"

    nil  # Return nil to allow booking flow to continue
  end
end
```

**What This Solves:**
- ✅ Bookings no longer crash when encountering corrupted phone data
- ✅ CustomerLinker gracefully degrades to email-based customer linking
- ✅ Detailed error logging for debugging and monitoring
- ✅ User experience maintained (can still book, just without phone matching)

**What This Doesn't Solve:**
- ❌ Phone data is lost (returns nil)
- ❌ SMS notifications won't work for affected customers
- ❌ Phone-based deduplication doesn't work
- ❌ Other services accessing phone data still vulnerable

### Commit 2: Rake Task - Clear Corrupted Data (`8888669`)

**File:** `lib/tasks/clear_corrupted_phone_data.rake`

**Tasks:**
1. `rake data:check_corrupted_phones` - Dry run, read-only scan
2. `rake data:clear_corrupted_phones` - Clears corrupted phone data

**Features:**
- Batch processing (100 records at a time)
- Progress indicators for long-running operations
- Comprehensive error handling and reporting
- Detailed summary of affected records
- Safe to run in production (dry-run mode available)

**What This Solves:**
- ✅ Identifies exactly which records have corrupted phone data
- ✅ Provides operational tool to clean up bad data
- ✅ Prevents future decryption errors on cleaned records
- ✅ Detailed reporting for audit and debugging

**What This Doesn't Solve:**
- ❌ Permanently deletes phone data (no recovery)
- ❌ Users must re-enter phone numbers
- ❌ Historical SMS records remain problematic

### Commit 3: Bug Fix - Undefined Variable (`510d057`)

**File:** `app/services/customer_linker.rb:434`

**Issue:** Variable `merged_canonical` only defined in one code path but used in another

**Fix:** Initialize `merged_canonical = nil` at method start

**Code Path:**
```ruby
def resolve_phone_conflicts_for_user(user)
  conflict_resolver = CustomerConflictResolver.new(@business)
  result = conflict_resolver.resolve_phone_conflicts_for_user(user, customer_finder: self)

  merged_canonical = nil  # FIX: Always defined in all code paths

  # ... rest of method
end
```

### Commit 4: Bug Fix - Decryption Errors in Logs (`0caffda`)

**File:** `app/services/customer_linker.rb:451-452, 546`

**Issue:** Log statements accessed encrypted fields directly, causing crashes

**Fix:** Use safe accessor before logging

**Example:**
```ruby
# BEFORE (crashed on decryption error)
SecureLogger.info "Merged customer: #{merged_canonical.id}, phone: #{merged_canonical.phone}"

# AFTER (safe)
merged_phone = safe_phone_access(merged_canonical)
SecureLogger.info "Merged customer: #{merged_canonical.id}, phone: #{merged_phone || 'N/A'}"
```

### Commit 5: Bug Fix - Inconsistent Phone Handling (`896973a`)

**File:** `app/services/customer_linker.rb:193-196`

**Issue:** Method used safe accessor for customer but direct access for user (3 times)

**Fix:** Use safe accessor consistently for both

**Example:**
```ruby
# BEFORE (inconsistent)
current_phone = safe_phone_access(customer)  # Safe
if !preserve_phone && user.phone.present? && current_phone != user.phone  # Direct access
  updates[:phone] = user.phone  # Direct access
end

# AFTER (consistent)
current_phone = safe_phone_access(customer)
user_phone = safe_phone_access(user)
if !preserve_phone && user_phone.present? && current_phone != user_phone
  updates[:phone] = user_phone
end
```

### Why These Hotfixes Are Safe to Deploy

**Non-Breaking Changes:**
- ✅ Defensive error handling only
- ✅ No schema changes
- ✅ No API changes
- ✅ No user-facing feature changes
- ✅ Graceful degradation (features continue with reduced functionality)

**Production-Ready:**
- ✅ Immediate stability improvement
- ✅ No rollback risk (can safely revert)
- ✅ No configuration changes required
- ✅ No data migration required
- ✅ Works with existing encryption keys

---

## Long-Term Solution Architecture

The long-term solution uses Rails Active Record Encryption's **`previous:` keys** feature to recover existing encrypted data and prevent future key rotation issues.

### Overview of 4 Phases

**Phase 1: Attribute-Level Key Rotation (Deterministic Fields)**
- Configure `previous:` keys for phone number fields
- Allows Rails to read old encrypted data
- Gradual re-encryption happens automatically

**Phase 2: Global Key Rotation (Non-Deterministic Fields)**
- Configure `previous:` keys in initializer
- Applies to tokens and passwords
- Add error handling for calendar services

**Phase 3: Data Re-Encryption Migration**
- Batch re-encrypt all records with current keys
- Remove dependency on old keys
- Comprehensive progress tracking

**Phase 4: Encryption Key Version Tracking**
- Track which key version encrypted each record
- Monitor key rotation events
- Prevent future key mismatch issues

---

## Phase 1: Attribute-Level Key Rotation (Deterministic Fields)

### Configuration Changes

**1. Environment Variables**

Add to `config/credentials.yml.enc` or environment:

```bash
# New environment variable for old deterministic key
ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY=<old_key_value>
```

**2. Model Changes - User.phone**

File: `app/models/user.rb` (line 37)

```ruby
# OLD:
encrypts :phone, deterministic: true

# NEW:
if ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY'].present?
  encrypts :phone,
    deterministic: true,
    previous: [{
      deterministic_key: ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY']
    }]
else
  encrypts :phone, deterministic: true
end
```

**3. Model Changes - TenantCustomer.phone**

File: `app/models/tenant_customer.rb` (line 28)

```ruby
# Same pattern as User.phone
if ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY'].present?
  encrypts :phone,
    deterministic: true,
    previous: [{
      deterministic_key: ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY']
    }]
else
  encrypts :phone, deterministic: true
end
```

**4. Model Changes - SmsMessage.phone_number**

File: `app/models/sms_message.rb` (line 20)

```ruby
# Add previous key support + error handling
if ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY'].present?
  encrypts :phone_number,
    deterministic: true,
    previous: [{
      deterministic_key: ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY']
    }]
else
  encrypts :phone_number, deterministic: true
end

# Add error handling in deliver method (line 68)
def deliver
  safe_phone = begin
    phone_number
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.error "[SMS_MESSAGE] Decryption error for SmsMessage #{id}: #{e.message}"
    Rails.logger.error "[SMS_MESSAGE] This message's phone data cannot be decrypted"
    nil
  end

  return false if safe_phone.nil?

  SmsNotificationJob.perform_later(safe_phone, content, metadata)
end
```

### How This Works

**Decryption Flow:**
1. Rails attempts to decrypt with **current** deterministic key
2. If decryption fails, Rails tries **old** deterministic key from `previous:` array
3. If decryption succeeds with old key, data is returned successfully
4. When record is saved, Rails **automatically re-encrypts** with current key
5. Gradual migration happens naturally as records are accessed

**Example:**
```ruby
# Record was encrypted with OLD key
user = User.find(123)

# Rails tries current key → fails
# Rails tries previous key → succeeds! ✅
phone = user.phone  # "+1234567890" (decrypted successfully)

# Update any field and save
user.first_name = "Updated"
user.save!  # Phone is now re-encrypted with CURRENT key

# Next read will use current key only (faster)
user.reload
user.phone  # Decrypted with current key ✅
```

### Benefits

✅ **Data Recovery** - All phone data becomes readable again
✅ **Zero Data Loss** - No need to clear corrupted records
✅ **Automatic Migration** - Re-encryption happens naturally
✅ **Non-Disruptive** - Users don't notice anything
✅ **Queryable** - Can still search by phone number

---

## Phase 2: Global Key Rotation (Non-Deterministic Fields)

### Configuration Changes

**1. Environment Variables**

Add to `config/credentials.yml.enc` or environment:

```bash
# New environment variables for old non-deterministic keys
ACTIVE_RECORD_ENCRYPTION_OLD_PRIMARY_KEY=<old_primary_key>
ACTIVE_RECORD_ENCRYPTION_OLD_KEY_DERIVATION_SALT=<old_salt>
```

**2. Global Configuration**

File: `config/initializers/active_record_encryption.rb`

```ruby
# Store old keys for fallback decryption
old_primary_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_OLD_PRIMARY_KEY', nil)
old_derivation_salt = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_OLD_KEY_DERIVATION_SALT', nil)

Rails.application.config.active_record.encryption.tap do |c|
  c.primary_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
  c.deterministic_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
  c.key_derivation_salt = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
  c.support_unencrypted_data = true

  # Add previous keys for non-deterministic encryption
  if old_primary_key.present? && old_derivation_salt.present?
    c.previous = [{
      primary_key: old_primary_key,
      key_derivation_salt: old_derivation_salt
    }]
  end
end
```

### Service Layer Error Handling

**1. CalDAV Service**

File: `app/services/calendar/caldav_service.rb` (line 14-18)

```ruby
def initialize(calendar_connection)
  super(calendar_connection)
  @username = calendar_connection.caldav_username

  # Add error handling for password decryption
  @password = begin
    calendar_connection.caldav_password
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.error "[CALDAV] Decryption error for CalendarConnection #{calendar_connection.id}: #{e.message}"
    Rails.logger.error "[CALDAV] User #{connection_connection.user_id} must re-enter CalDAV credentials"
    nil
  end

  @server_url = calendar_connection.caldav_url
  validate_credentials
end

def validate_credentials
  raise CalDAVError, "Missing CalDAV password - please re-enter credentials" if @password.nil?
  # ... rest of validation
end
```

**2. Google Calendar Service**

File: `app/services/calendar/google_service.rb` (line 172)

```ruby
def refresh_access_token
  current_refresh_token = begin
    @calendar_connection.refresh_token
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.error "[GOOGLE_CALENDAR] Decryption error for refresh_token: #{e.message}"
    raise Calendar::ReauthorizationRequired, "Calendar connection requires reauthorization"
  end

  return nil if current_refresh_token.nil?

  # ... existing OAuth refresh logic
end
```

**3. OAuth Handler**

File: `app/services/calendar/oauth_handler.rb` (line 223)

```ruby
def request_new_token(refresh_token_param = nil)
  token_to_use = refresh_token_param || begin
    @calendar_connection.refresh_token
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.error "[OAUTH] Decryption error for refresh_token: #{e.message}"
    nil
  end

  raise Calendar::ReauthorizationRequired, "Token unavailable - please reauthorize" if token_to_use.nil?

  # ... existing token request logic
end
```

### Benefits

✅ **Calendar Sync Restored** - OAuth tokens become readable
✅ **Graceful Degradation** - Prompts user to reauthorize if unrecoverable
✅ **Global Configuration** - Applies to all non-deterministic fields
✅ **User-Friendly** - Clear error messages guide reauthorization

---

## Phase 3: Data Re-Encryption Migration

### Purpose

Gradually re-encrypt all data with current keys to remove dependency on `previous:` keys configuration.

### Implementation

File: `lib/tasks/re_encrypt_data.rake`

```ruby
namespace :encryption do
  desc 'Re-encrypt all phone data with current encryption keys'
  task re_encrypt_phones: :environment do
    puts "=" * 80
    puts "RE-ENCRYPT PHONE DATA MIGRATION"
    puts "=" * 80
    puts "This task re-encrypts all phone data with current encryption keys"
    puts "Started at: #{Time.current}"
    puts "=" * 80
    puts

    users_re_encrypted = 0
    customers_re_encrypted = 0
    sms_messages_re_encrypted = 0
    errors = 0

    # Re-encrypt User phones
    puts "Phase 1: Re-encrypting User phone numbers..."
    User.where.not(phone: nil).find_in_batches(batch_size: 100) do |batch|
      batch.each do |user|
        begin
          # Reading triggers decryption with previous keys
          # Saving triggers encryption with current keys
          current_phone = user.phone
          user.save! if current_phone.present?
          users_re_encrypted += 1
          print "."
        rescue => e
          errors += 1
          puts "\n✗ Failed to re-encrypt User #{user.id}: #{e.message}"
        end
      end
    end

    puts "\nPhase 1 Complete: #{users_re_encrypted} users re-encrypted"

    # Re-encrypt TenantCustomer phones
    puts "Phase 2: Re-encrypting TenantCustomer phone numbers..."
    TenantCustomer.where.not(phone: nil).find_in_batches(batch_size: 100) do |batch|
      batch.each do |customer|
        begin
          current_phone = customer.phone
          customer.save! if current_phone.present?
          customers_re_encrypted += 1
          print "."
        rescue => e
          errors += 1
          puts "\n✗ Failed to re-encrypt Customer #{customer.id}: #{e.message}"
        end
      end
    end

    puts "\nPhase 2 Complete: #{customers_re_encrypted} customers re-encrypted"

    # Re-encrypt SmsMessage phone numbers
    puts "Phase 3: Re-encrypting SmsMessage phone numbers..."
    SmsMessage.where.not(phone_number: nil).find_in_batches(batch_size: 100) do |batch|
      batch.each do |message|
        begin
          current_phone = message.phone_number
          message.save! if current_phone.present?
          sms_messages_re_encrypted += 1
          print "."
        rescue => e
          errors += 1
          puts "\n✗ Failed to re-encrypt SmsMessage #{message.id}: #{e.message}"
        end
      end
    end

    puts "\nPhase 3 Complete: #{sms_messages_re_encrypted} SMS messages re-encrypted"

    puts "\n"
    puts "=" * 80
    puts "MIGRATION COMPLETE"
    puts "=" * 80
    puts "Summary:"
    puts "  Users re-encrypted:        #{users_re_encrypted}"
    puts "  Customers re-encrypted:    #{customers_re_encrypted}"
    puts "  SMS messages re-encrypted: #{sms_messages_re_encrypted}"
    puts "  Errors:                    #{errors}"
    puts
    puts "Next Steps:"
    puts "  1. ✓ All readable data has been re-encrypted with current keys"
    puts "  2. → Monitor for 30 days to ensure no records still using old keys"
    puts "  3. → After verification, remove ACTIVE_RECORD_ENCRYPTION_OLD_* env vars"
    puts "  4. → Remove 'previous:' configurations from models"
    puts "=" * 80
  end

  desc 'Re-encrypt CalendarConnection tokens with current encryption keys'
  task re_encrypt_calendar_tokens: :environment do
    puts "=" * 80
    puts "RE-ENCRYPT CALENDAR TOKENS MIGRATION"
    puts "=" * 80

    re_encrypted = 0
    errors = 0

    CalendarConnection.find_in_batches(batch_size: 50) do |batch|
      batch.each do |connection|
        begin
          # Reading triggers decryption with previous keys
          # Saving triggers encryption with current keys
          _ = connection.access_token if connection.access_token.present?
          _ = connection.refresh_token if connection.refresh_token.present?
          _ = connection.caldav_password if connection.caldav_password.present?

          connection.save!
          re_encrypted += 1
          print "."
        rescue => e
          errors += 1
          puts "\n✗ Failed to re-encrypt CalendarConnection #{connection.id}: #{e.message}"
          puts "   User #{connection.user_id} will need to reauthorize calendar"
        end
      end
    end

    puts "\n"
    puts "=" * 80
    puts "MIGRATION COMPLETE"
    puts "=" * 80
    puts "  Re-encrypted: #{re_encrypted}"
    puts "  Errors:       #{errors}"
    puts "=" * 80
  end
end
```

### Usage

```bash
# Production deployment
RAILS_ENV=production bundle exec rake encryption:re_encrypt_phones
RAILS_ENV=production bundle exec rake encryption:re_encrypt_calendar_tokens
```

### Benefits

✅ **Gradual Migration** - Batch processing prevents performance impact
✅ **Progress Tracking** - Real-time progress indicators
✅ **Error Handling** - Continues despite individual failures
✅ **Detailed Reporting** - Comprehensive summary of results
✅ **Removes Dependency** - Eventually eliminates need for `previous:` keys

---

## Phase 4: Encryption Key Version Tracking

### Purpose

Track which encryption key version was used for each record to prevent future key mismatch issues.

### Implementation

**1. Encryption Key Version Module**

File: `config/initializers/encryption_key_version.rb`

```ruby
module EncryptionKeyVersion
  CURRENT_VERSION = ENV.fetch('ENCRYPTION_KEY_VERSION', 'v1')

  def self.log_key_info
    Rails.logger.info "[ENCRYPTION] Key version: #{CURRENT_VERSION}"
    Rails.logger.info "[ENCRYPTION] Primary key configured: #{ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?}"
    Rails.logger.info "[ENCRYPTION] Deterministic key configured: #{ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY'].present?}"
    Rails.logger.info "[ENCRYPTION] Previous keys configured: #{ENV['ACTIVE_RECORD_ENCRYPTION_OLD_PRIMARY_KEY'].present?}"
  end
end

# Log key version on app boot
Rails.application.config.after_initialize do
  EncryptionKeyVersion.log_key_info
end
```

**2. Encryption Error Tracking Concern**

File: `app/models/concerns/encryption_error_tracking.rb`

```ruby
module EncryptionErrorTracking
  extend ActiveSupport::Concern

  included do
    after_create :log_encryption_key_version
  end

  private

  def log_encryption_key_version
    # Track which key version was used for encryption
    Rails.logger.info "[ENCRYPTION] #{self.class.name} #{id} created with key version: #{EncryptionKeyVersion::CURRENT_VERSION}"
  end
end
```

**3. Include in Models**

Add to models with encrypted attributes:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include EncryptionErrorTracking
  # ... rest of model
end

# app/models/tenant_customer.rb
class TenantCustomer < ApplicationRecord
  include EncryptionErrorTracking
  # ... rest of model
end

# app/models/sms_message.rb
class SmsMessage < ApplicationRecord
  include EncryptionErrorTracking
  # ... rest of model
end

# app/models/calendar_connection.rb
class CalendarConnection < ApplicationRecord
  include EncryptionErrorTracking
  # ... rest of model
end
```

### Environment Configuration

Add to `config/credentials.yml.enc`:

```yaml
encryption:
  key_version: v2  # Increment when rotating keys
```

Set environment variable:

```bash
ENCRYPTION_KEY_VERSION=v2
```

### Benefits

✅ **Key Version Tracking** - Know which key was used for each record
✅ **Audit Trail** - Track key rotation events in logs
✅ **Debugging** - Quickly identify records encrypted with old keys
✅ **Monitoring** - Alert when old key versions still in use
✅ **Prevents Future Issues** - Catch key rotation problems early

---

## Implementation Roadmap

### Week 1: Deploy Hotfixes + Data Cleanup

**Day 1-2: Deploy Hotfixes**
- [ ] Deploy commit `5885ef7` - CustomerLinker error handling
- [ ] Deploy commit `8888669` - Rake tasks for data cleanup
- [ ] Deploy commits `510d057`, `0caffda`, `896973a` - Bug fixes
- [ ] Monitor production logs for decryption errors
- [ ] Verify booking flow works correctly

**Day 3-4: Assess Damage**
- [ ] Run `RAILS_ENV=production bundle exec rake data:check_corrupted_phones`
- [ ] Document number of affected users and customers
- [ ] Identify patterns in corrupted data
- [ ] Determine if encryption keys actually changed (compare with backups)

**Day 5-7: Clean Corrupted Data**
- [ ] Run `RAILS_ENV=production bundle exec rake data:clear_corrupted_phones`
- [ ] Verify no more decryption errors in production logs
- [ ] Monitor user reports and support tickets
- [ ] Document cleanup results

**Milestone:** Production stable, booking flow working, corrupted data cleaned

---

### Week 2-3: Configure Previous Keys

**Day 8-10: Determine Old Encryption Keys**
- [ ] Review `config/credentials.yml.enc` history
- [ ] Check environment variable history in hosting platform
- [ ] Identify when keys changed (if they did)
- [ ] Document old key values (store securely)
- [ ] Verify old keys with test decryption

**Day 11-12: Configure Environment**
- [ ] Add `ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY` to credentials
- [ ] Add `ACTIVE_RECORD_ENCRYPTION_OLD_PRIMARY_KEY` to credentials
- [ ] Add `ACTIVE_RECORD_ENCRYPTION_OLD_KEY_DERIVATION_SALT` to credentials
- [ ] Add `ENCRYPTION_KEY_VERSION=v2` to environment
- [ ] Test in development environment first

**Day 13-15: Implement Phase 1 (Deterministic Fields)**
- [ ] Update `User` model with `previous:` keys for phone
- [ ] Update `TenantCustomer` model with `previous:` keys for phone
- [ ] Update `SmsMessage` model with `previous:` keys + error handling
- [ ] Test with known corrupted records in staging
- [ ] Verify old encrypted data becomes readable

**Day 16-18: Implement Phase 2 (Non-Deterministic Fields)**
- [ ] Update `config/initializers/active_record_encryption.rb` with global `previous:` keys
- [ ] Add error handling to `CalDAVService`
- [ ] Add error handling to `GoogleService`
- [ ] Add error handling to `OAuthHandler`
- [ ] Test calendar sync with old encrypted tokens in staging

**Day 19-21: Deploy to Production**
- [ ] Deploy Phase 1 + Phase 2 code changes
- [ ] Monitor logs for successful old key decryptions
- [ ] Test booking flow with previously corrupted users
- [ ] Test SMS delivery to previously corrupted customers
- [ ] Test calendar sync for users with old tokens
- [ ] Verify no new decryption errors

**Milestone:** All encrypted data readable, no decryption errors, full functionality restored

---

### Week 4-6: Re-Encrypt Data with Current Keys

**Day 22-24: Prepare Re-Encryption Tasks**
- [ ] Implement `lib/tasks/re_encrypt_data.rake`
- [ ] Add comprehensive error handling
- [ ] Add progress tracking and reporting
- [ ] Test rake tasks in staging environment
- [ ] Plan production execution schedule (off-peak hours)

**Day 25-27: Re-Encrypt Phone Data**
- [ ] Schedule maintenance window (optional - non-disruptive)
- [ ] Run `rake encryption:re_encrypt_phones` in production
- [ ] Monitor progress and logs
- [ ] Verify re-encrypted records decrypt with current key only
- [ ] Document number of records re-encrypted

**Day 28-30: Re-Encrypt Calendar Tokens**
- [ ] Run `rake encryption:re_encrypt_calendar_tokens` in production
- [ ] Monitor calendar sync for any issues
- [ ] Track users who need to reauthorize (if any)
- [ ] Document results

**Day 31-42: Monitor and Verify**
- [ ] Monitor logs daily for old key usage
- [ ] Track percentage of records still using old keys
- [ ] Re-run re-encryption tasks weekly if needed
- [ ] Verify gradual migration through natural record updates

**Milestone:** 95%+ of data re-encrypted with current keys, minimal old key usage

---

### Month 3: Remove Old Keys and Complete Migration

**Day 43-50: Verification Period**
- [ ] Monitor for 30 days after Phase 3 completion
- [ ] Ensure no records still triggering old key decryption
- [ ] Verify all critical user flows working
- [ ] Review error logs for any encryption-related issues

**Day 51-53: Remove Old Keys**
- [ ] Remove `ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY` from credentials
- [ ] Remove `ACTIVE_RECORD_ENCRYPTION_OLD_PRIMARY_KEY` from credentials
- [ ] Remove `ACTIVE_RECORD_ENCRYPTION_OLD_KEY_DERIVATION_SALT` from credentials
- [ ] Test in staging first
- [ ] Deploy to production

**Day 54-56: Clean Up Code**
- [ ] Remove `previous:` configuration from User model
- [ ] Remove `previous:` configuration from TenantCustomer model
- [ ] Remove `previous:` configuration from SmsMessage model
- [ ] Remove `previous:` configuration from initializer
- [ ] Remove conditional checks for old keys

**Day 57-60: Deploy Phase 4 (Key Version Tracking)**
- [ ] Implement encryption key version tracking
- [ ] Add logging on record creation
- [ ] Set up monitoring alerts for key version changes
- [ ] Document current encryption key version
- [ ] Create runbook for future key rotations

**Milestone:** ✅ Complete migration, old keys removed, key version tracking active

---

## Comparison: Hotfixes vs Long-Term Solution

| Aspect | Current Hotfixes | Long-Term Solution |
|--------|-----------------|-------------------|
| **Production Stability** | ✅ Immediate fix - Bookings work | ✅ Permanent fix - All features work |
| **Data Preservation** | ❌ Loses phone data (returns nil) | ✅ Recovers ALL encrypted data |
| **SMS Delivery** | ❌ Still vulnerable to crashes | ✅ Protected with error handling |
| **Calendar Sync** | ❌ Still vulnerable to crashes | ✅ Protected with graceful reauth |
| **Future Key Rotation** | ❌ Will break again | ✅ Handles gracefully with `previous:` keys |
| **User Experience** | 🟡 Degraded (no SMS, re-enter phone) | ✅ Full functionality restored |
| **Technical Debt** | 🔴 Increases (defensive patches) | ✅ Eliminates (proper key management) |
| **Deployment Complexity** | 🟢 Low (5 commits, no config) | 🟡 Medium (env vars + migrations) |
| **Risk Level** | 🟢 Low (defensive, non-breaking) | 🟡 Medium (config changes, testing) |
| **Time to Deploy** | 🟢 Immediate (< 1 day) | 🟡 6-12 weeks (4 phases) |
| **Team Knowledge Required** | 🟢 Low (standard error handling) | 🔴 High (encryption internals) |
| **Operational Overhead** | 🟡 Medium (monitor logs, run rake tasks) | 🟢 Low (automated, self-healing) |
| **Data Recovery Cost** | 🔴 High (users re-enter data) | 🟢 None (automatic recovery) |
| **Compliance/Audit** | 🟡 May require data loss reporting | ✅ No data loss, full audit trail |
| **Monitoring Required** | 🔴 High (watch for SMS/calendar failures) | 🟢 Low (key version tracking) |

### Decision Matrix

**Deploy Hotfixes When:**
- ✅ Production is down or severely degraded
- ✅ Need immediate stability
- ✅ Don't have old encryption keys
- ✅ Data loss is acceptable short-term
- ✅ Want to buy time for proper fix

**Deploy Long-Term Solution When:**
- ✅ Have identified old encryption keys
- ✅ Want to recover lost data
- ✅ Need all features fully functional
- ✅ Want to prevent future key rotation issues
- ✅ Have capacity for multi-week project

**Recommended Approach: Both (Sequential)**
1. **Week 1:** Deploy hotfixes for immediate stability
2. **Week 2-3:** Configure old keys and deploy Phase 1-2
3. **Week 4-6:** Re-encrypt data with Phase 3
4. **Month 3:** Complete migration with Phase 4

---

## Decision Log

### Decision 1: Deploy Hotfixes First
**Date:** October 29, 2025
**Decision:** Deploy 5 hotfix commits before starting long-term solution
**Rationale:**
- Production bookings are failing (critical business impact)
- Hotfixes are non-breaking and low-risk
- Provides immediate stability while planning long-term fix
- Buys time to locate old encryption keys
- Users can continue booking (even without phone matching)

**Alternatives Considered:**
- Wait for long-term solution (rejected - too slow, business impact)
- Only deploy rake tasks to clear data (rejected - doesn't fix booking crashes)
- Disable encryption entirely (rejected - security/compliance risk)

### Decision 2: Use Rails `previous:` Keys Instead of Custom Solution
**Date:** October 29, 2025
**Decision:** Leverage Rails Active Record Encryption's built-in `previous:` keys feature
**Rationale:**
- Official Rails feature, well-documented and tested
- Automatic re-encryption on record save
- No custom encryption code to maintain
- Works with both deterministic and non-deterministic fields
- Gradual migration without downtime

**Alternatives Considered:**
- Custom decryption layer (rejected - maintenance burden, reinventing wheel)
- Dual encryption (encrypt with both keys) (rejected - storage overhead)
- Full re-encryption with downtime (rejected - business impact)
- Manual decryption/re-encryption scripts (rejected - error-prone)

### Decision 3: Separate Attribute-Level and Global Key Configuration
**Date:** October 29, 2025
**Decision:** Use attribute-level `previous:` for deterministic fields, global for non-deterministic
**Rationale:**
- Rails doesn't support global key rotation for deterministic encryption
- Deterministic fields need per-attribute configuration
- Non-deterministic fields benefit from single global config
- Separates concerns: phone matching vs API tokens

**Alternatives Considered:**
- All attribute-level (rejected - redundant for non-deterministic)
- All global (rejected - doesn't work for deterministic)
- Convert deterministic to non-deterministic (rejected - breaks phone queries)

### Decision 4: Gradual Re-Encryption Over Forced Migration
**Date:** October 29, 2025
**Decision:** Allow natural record updates to trigger re-encryption, supplemented by batch rake tasks
**Rationale:**
- Zero downtime
- Distributes load over time
- No user-facing disruption
- Rake tasks for faster completion
- Records that are never updated eventually handled by cleanup scripts

**Alternatives Considered:**
- Force immediate re-encryption (rejected - database load, downtime)
- Only natural updates (rejected - some records never updated)
- Scheduled batch jobs (rejected - complex scheduling)

### Decision 5: Add Service Layer Error Handling for Calendar/SMS
**Date:** October 29, 2025
**Decision:** Wrap all encrypted field access in calendar and SMS services with error handling
**Rationale:**
- Provides defense-in-depth beyond database layer
- Allows graceful degradation (prompt for reauthorization)
- Better user experience than crashes
- Catches edge cases where `previous:` keys don't work
- Complements model-level encryption configuration

**Alternatives Considered:**
- Model-level callbacks only (rejected - too late, errors already raised)
- Global exception handler (rejected - too coarse, can't provide context)
- Remove error handling after migration (rejected - future key rotation protection)

### Decision 6: Keep Password Handling Separate
**Date:** October 29, 2025
**Decision:** Treat Devise bcrypt passwords differently from CalDAV encrypted passwords
**Rationale:**
- Bcrypt hashing not affected by Active Record Encryption
- CalDAV passwords use Active Record Encryption (reversible)
- Different security models, different failure modes
- Prevents confusion in documentation and implementation

**Alternatives Considered:**
- Treat all passwords the same (rejected - technically incorrect)
- Convert CalDAV to hashing (rejected - need plaintext for auth)
- Ignore password distinction (rejected - causes confusion)

---

## Technical References

### Rails Active Record Encryption Documentation
- [Rails 7.0 Active Record Encryption Guide](https://edgeguides.rubyonrails.org/active_record_encryption.html)
- [Key Rotation Best Practices](https://edgeguides.rubyonrails.org/active_record_encryption.html#key-rotation)
- [Previous Keys Configuration](https://edgeguides.rubyonrails.org/active_record_encryption.html#previous-encryption-schemes)
- [Deterministic vs Non-Deterministic Encryption](https://edgeguides.rubyonrails.org/active_record_encryption.html#deterministic-encryption)

### GitHub Engineering Blog Posts
- [How GitHub Uses Active Record Encryption](https://github.blog/2022-04-04-how-github-uses-rails-active-record-encryption/)
- [Encryption at Rest Best Practices](https://docs.github.com/en/enterprise-server/admin/configuration/encryption-at-rest)

### Encryption Key Management
- [OWASP Key Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html)
- [Rails Credentials Management](https://guides.rubyonrails.org/security.html#custom-credentials)

### Related Issues & Discussions
- [Rails Issue: Deterministic Encryption Key Rotation](https://github.com/rails/rails/issues/43746)
- [StackOverflow: Rails 7 Encryption Key Rotation](https://stackoverflow.com/questions/70234567/rails-7-active-record-encryption-key-rotation)

### Internal Documentation
- `docs/CSRF_ALERTS_REMEDIATION.md` - Similar security fix documentation pattern
- `docs/CROSS_DOMAIN_SSO_IMPLEMENTATION.md` - Multi-phase implementation example
- `docs/SMS_TESTING_README.md` - SMS system overview
- `docs/CALENDAR_INTEGRATION_SETUP.md` - Calendar integration setup

### Security & Compliance
- GDPR Right to Erasure (phone data deletion)
- CCPA Data Portability (encrypted data must be recoverable)
- SOC 2 Encryption Key Management requirements
- PCI DSS Encryption Standards (if applicable)

---

## Appendix A: Encryption Key Checklist

Use this checklist when rotating encryption keys in the future:

### Before Key Rotation
- [ ] Document current key version (e.g., v1)
- [ ] Back up current encryption keys securely
- [ ] Identify all encrypted attributes in application
- [ ] Review this strategy document
- [ ] Test key rotation in staging environment
- [ ] Plan rollback procedure

### During Key Rotation
- [ ] Generate new encryption keys
- [ ] Store old keys as `ACTIVE_RECORD_ENCRYPTION_OLD_*` variables
- [ ] Configure `previous:` keys in models/initializers
- [ ] Update `ENCRYPTION_KEY_VERSION` environment variable
- [ ] Deploy configuration changes
- [ ] Monitor logs for successful old key decryptions
- [ ] Verify all features still functional

### After Key Rotation
- [ ] Run re-encryption rake tasks
- [ ] Monitor progress weekly
- [ ] Wait 30 days for verification
- [ ] Remove old keys from configuration
- [ ] Remove `previous:` configurations from code
- [ ] Update documentation with new key version
- [ ] Create incident report/postmortem

---

## Appendix B: Troubleshooting Guide

### Issue: Decryption Still Failing After Configuring Previous Keys

**Symptoms:** `ActiveRecord::Encryption::Errors::Decryption` still raised

**Possible Causes:**
1. Old keys don't match the keys used for encryption
2. Typo in environment variable configuration
3. Credentials not reloaded after update
4. Wrong key derivation salt

**Debugging Steps:**
```ruby
# Test if old key can decrypt in Rails console
old_key = ENV['ACTIVE_RECORD_ENCRYPTION_OLD_DETERMINISTIC_KEY']
puts "Old key configured: #{old_key.present?}"

# Try manual decryption
user = User.find(<id_with_corrupted_phone>)
begin
  phone = user.phone
  puts "✅ Decryption successful: #{phone}"
rescue ActiveRecord::Encryption::Errors::Decryption => e
  puts "❌ Decryption failed: #{e.message}"
end

# Check if previous keys are being used
puts Rails.application.config.active_record.encryption.previous.inspect
```

**Resolution:**
- Verify old keys match actual keys used for encryption
- Check environment variable spelling and capitalization
- Restart Rails application after credentials update
- Review hosting platform environment configuration

### Issue: Re-Encryption Rake Task Running Slowly

**Symptoms:** Task takes hours to complete, database load high

**Possible Causes:**
1. Large dataset (millions of records)
2. Batch size too large
3. Database under heavy production load
4. N+1 query issues
5. Callbacks triggering expensive operations

**Debugging Steps:**
```ruby
# Check record counts
puts "Users with phones: #{User.where.not(phone: nil).count}"
puts "Customers with phones: #{TenantCustomer.where.not(phone: nil).count}"
puts "SMS messages with phones: #{SmsMessage.where.not(phone_number: nil).count}"

# Monitor database queries
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Time a single batch
require 'benchmark'
time = Benchmark.measure do
  User.where.not(phone: nil).limit(100).each do |user|
    user.phone
    user.save!
  end
end
puts "Batch of 100 took: #{time.real} seconds"
```

**Resolution:**
- Reduce batch size (50 instead of 100)
- Run during off-peak hours
- Temporarily disable callbacks with `update_column` for specific fields
- Use separate read replica for queries
- Split task by date ranges or ID ranges

### Issue: Some Records Still Using Old Keys After Migration

**Symptoms:** Old key decryption still happening weeks after Phase 3

**Possible Causes:**
1. Records never updated (stale data)
2. Read-only records (archived, historical)
3. Re-encryption task skipped some records due to errors
4. Records created between task runs

**Debugging Steps:**
```ruby
# Find records still using old key
User.where.not(phone: nil).find_each do |user|
  begin
    # Try decrypting with current key only (no previous)
    # This would fail if using old key
    user.phone
  rescue ActiveRecord::Encryption::Errors::Decryption
    puts "User #{user.id} still using old key"
  end
end
```

**Resolution:**
- Re-run re-encryption tasks
- Manually update specific problematic records
- If records are truly stale (not accessed), clear encrypted data
- Consider scheduled background job to re-encrypt on first access

---

## Appendix C: Communication Templates

### Template 1: Informing Users of Phone Number Re-Entry

**Subject:** Action Required: Please Update Your Phone Number

**Body:**
```
Hi [User Name],

We recently performed a security upgrade to our encryption system to better protect your data.

As part of this upgrade, we need you to re-enter your phone number if you'd like to continue receiving SMS notifications for bookings and appointments.

To update your phone number:
1. Log in to your account
2. Go to Settings > Profile
3. Enter your phone number
4. Save changes

This is a one-time update and will only take a moment. Your booking history and other account information remain unchanged.

If you have any questions, please don't hesitate to contact our support team.

Thank you for your understanding!

[Company Name] Team
```

### Template 2: Notifying Team of Key Rotation

**Subject:** [ALERT] Encryption Key Rotation Scheduled

**Body:**
```
Team,

We are performing an encryption key rotation on [DATE] at [TIME].

Impact:
- Brief read-only mode for data migration (15-30 minutes)
- Users may need to re-enter phone numbers
- Calendar connections may require reauthorization

Pre-Deployment Checklist:
- [ ] Old keys backed up securely
- [ ] Previous keys configured in environment
- [ ] Staging tests passed
- [ ] Rollback plan documented
- [ ] On-call engineer assigned

Post-Deployment:
- Monitor logs for decryption errors
- Run re-encryption rake tasks
- Track user reports of issues
- Update incident channel with progress

Point of Contact: [Name, Slack Handle]

Documentation: docs/ENCRYPTION_KEY_ROTATION_STRATEGY.md
```

---

**End of Document**

---

**Next Actions:**
1. ✅ Deploy hotfixes (Week 1)
2. ⏳ Locate old encryption keys (Week 2)
3. ⏳ Implement Phase 1-2 (Week 2-3)
4. ⏳ Run Phase 3 migrations (Week 4-6)
5. ⏳ Complete Phase 4 cleanup (Month 3)

**Questions or Issues?**
Contact the engineering team or create a GitHub issue with tag `encryption`.
