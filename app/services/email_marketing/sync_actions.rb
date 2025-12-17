# frozen_string_literal: true

module EmailMarketing
  # Constants for sync action types used in email marketing integrations
  # These actions determine how a customer record is handled during sync:
  # - SYNC: Add or update customer in the email marketing platform
  # - REMOVE: Remove customer from the email marketing platform (e.g., when deactivated)
  # - OPT_OUT: Update customer's subscription status to unsubscribed/opted-out
  module SyncActions
    SYNC = 'sync'
    REMOVE = 'remove'
    OPT_OUT = 'opt_out'

    ALL = [SYNC, REMOVE, OPT_OUT].freeze

    def self.valid?(action)
      ALL.include?(action)
    end
  end
end
