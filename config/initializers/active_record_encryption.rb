# frozen_string_literal: true

# Configure Active Record Encryption using keys supplied entirely via environment
# variables (per project convention: no Rails credentials).
#
# IMPORTANT: In non-test environments, we MUST fail fast if keys are missing to prevent
# production misconfiguration. Only the test environment is allowed to use fallback values
# (configured in config/environments/test.rb) for CI environments like Dependabot PRs
# that don't have access to secrets.
if Rails.env.test?
  # Test environment: Allow fallback to test.rb config if keys are missing (for CI/Dependabot)
  if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present? &&
     ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY'].present? &&
     ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'].present?
    Rails.application.config.active_record.encryption.tap do |c|
      c.primary_key             = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
      c.deterministic_key       = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
      c.key_derivation_salt     = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
      c.support_unencrypted_data = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED', 'true') == 'true'
    end
  end
  # If keys are missing in test, the fallback values from config/environments/test.rb will be used
else
  # Production/Development: FAIL FAST if keys are missing (fail-fast is critical for production safety)
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
