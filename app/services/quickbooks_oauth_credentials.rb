# frozen_string_literal: true

# QuickbooksOauthCredentials provides environment-aware access to Intuit OAuth credentials.
#
# Expected ENV vars:
# - Production: QUICKBOOKS_CLIENT_ID, QUICKBOOKS_CLIENT_SECRET
# - Dev/Test:   QUICKBOOKS_CLIENT_ID_DEV, QUICKBOOKS_CLIENT_SECRET_DEV
class QuickbooksOauthCredentials
  class << self
    def client_id
      if Rails.env.development? || Rails.env.test?
        ENV['QUICKBOOKS_CLIENT_ID_DEV']
      else
        ENV['QUICKBOOKS_CLIENT_ID']
      end
    end

    def client_secret
      if Rails.env.development? || Rails.env.test?
        ENV['QUICKBOOKS_CLIENT_SECRET_DEV']
      else
        ENV['QUICKBOOKS_CLIENT_SECRET']
      end
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    def credentials
      { client_id: client_id, client_secret: client_secret }
    end

    def environment
      (Rails.env.development? || Rails.env.test?) ? 'development' : 'production'
    end
  end
end
