# frozen_string_literal: true

# Configure Active Record Encryption using keys supplied entirely via environment
# variables (per project convention: no Rails credentials).
Rails.application.config.active_record.encryption.tap do |c|
  c.primary_key             = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
  c.deterministic_key       = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
  c.key_derivation_salt     = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')

  # Allow reading clear-text data until the back-fill migration finishes.
  # After backfill completes in all environments, set ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED=false
  # to enforce encrypted-only data access for enhanced security.
  c.support_unencrypted_data = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED', 'true') == 'true'
end
