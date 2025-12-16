# frozen_string_literal: true

# Service class for managing Constant Contact OAuth credentials
# Follows the same pattern as QuickbooksOauthCredentials
class ConstantContactOauthCredentials
  class << self
    def client_id
      ENV.fetch('CONSTANT_CONTACT_CLIENT_ID', nil)
    end

    def client_secret
      ENV.fetch('CONSTANT_CONTACT_CLIENT_SECRET', nil)
    end

    def api_key
      ENV.fetch('CONSTANT_CONTACT_API_KEY', nil)
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    def authorize_url
      'https://authz.constantcontact.com/oauth2/default/v1/authorize'
    end

    def token_url
      'https://authz.constantcontact.com/oauth2/default/v1/token'
    end

    def api_base_url
      'https://api.cc.email/v3'
    end

    def scopes
      # Constant Contact OAuth scopes
      'contact_data offline_access'
    end
  end
end
