# frozen_string_literal: true

# Configure Active Record Encryption using keys supplied entirely via environment
# variables (per project convention: no Rails credentials).
#
# IMPORTANT: This initializer is SKIPPED in test environment because config/environments/test.rb
# already handles encryption setup with proper fallback values for CI/Dependabot.
# In production/development, we fail fast if keys are missing.
unless Rails.env.test?
  # Production/Development: FAIL FAST if keys are missing (critical for production safety)
  Rails.application.config.active_record.encryption.tap do |c|
    c.primary_key             = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
    c.deterministic_key       = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
    c.key_derivation_salt     = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')

    # Allow reading clear-text data until the back-fill migration finishes.
    # After backfill completes in all environments, set ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED=false
    # to enforce encrypted-only data access for enhanced security.
    c.support_unencrypted_data = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED', 'true') == 'true'
  end
end
