# frozen_string_literal: true

module BridgeHelpers
  # Helper for following the two-hop authentication bridge flow
  # 1. First redirect goes to /auth/bridge on main domain
  # 2. Second redirect goes to target domain with token
  def follow_bridge_redirect(response = nil)
    response ||= self.response
    
    # Follow the redirect to get the consumption URL with token
    follow_redirect!
    
    # Extract token from the consumption URL query parameters
    if response.location.present?
      uri = URI.parse(response.location)
      if uri.query.present?
        return URI.decode_www_form(uri.query).to_h['auth_token']
      end
    end
    
    nil
  rescue URI::InvalidURIError => e
    Rails.logger.warn "[BridgeHelpers] Invalid URI in redirect: #{e.message}"
    nil
  end
  
  # Extract token from current response location without following redirect
  def extract_token_from_location(response = nil)
    response ||= self.response
    
    return nil unless response.location.present?
    
    uri = URI.parse(response.location)
    return nil unless uri.query.present?
    
    URI.decode_www_form(uri.query).to_h['auth_token']
  rescue URI::InvalidURIError
    nil
  end
end
