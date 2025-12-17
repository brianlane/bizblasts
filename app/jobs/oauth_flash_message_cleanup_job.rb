# frozen_string_literal: true

# Cleans up used and expired OAuth flash message records
# These records are used for cross-domain flash messages during OAuth callbacks
# and should be cleaned up after they expire or are consumed.
class OauthFlashMessageCleanupJob < ApplicationJob
  queue_as :default

  def perform
    deleted_count = OauthFlashMessage.cleanup_old_records
    Rails.logger.info "[OauthFlashMessageCleanupJob] Cleaned up #{deleted_count} old OAuth flash message records"
  end
end
