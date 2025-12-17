# frozen_string_literal: true

# Service class for managing Mailchimp OAuth credentials
# Follows the same pattern as QuickbooksOauthCredentials
class MailchimpOauthCredentials
  class << self
    def client_id
      ENV.fetch('MAILCHIMP_CLIENT_ID', nil)
    end

    def client_secret
      ENV.fetch('MAILCHIMP_CLIENT_SECRET', nil)
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    def authorize_url
      'https://login.mailchimp.com/oauth2/authorize'
    end

    def token_url
      'https://login.mailchimp.com/oauth2/token'
    end

    def metadata_url
      'https://login.mailchimp.com/oauth2/metadata'
    end

    # Mailchimp uses datacenter-specific API endpoints
    def api_base_url(datacenter)
      "https://#{datacenter}.api.mailchimp.com/3.0"
    end

    def scopes
      # Mailchimp doesn't require explicit scopes in OAuth flow
      nil
    end
  end
end
