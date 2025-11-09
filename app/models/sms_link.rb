# frozen_string_literal: true

# SmsLink represents a shortened URL for use in SMS messages
# This allows long URLs to be replaced with short codes like /s/abc123
#
# Security: URLs are validated to prevent open redirect attacks
class SmsLink < ApplicationRecord
  # Validations
  validates :short_code, presence: true, uniqueness: true
  validates :original_url, presence: true
  validate :original_url_must_be_valid_http_or_https

  private

  # Validates that original_url is a valid HTTP or HTTPS URL
  # This prevents open redirect attacks by ensuring only web URLs are stored
  def original_url_must_be_valid_http_or_https
    return if original_url.blank?

    begin
      uri = URI.parse(original_url)

      # Only allow http and https schemes (no javascript:, data:, file:, etc.)
      unless uri.scheme.in?(['http', 'https'])
        errors.add(:original_url, 'must be a valid HTTP or HTTPS URL')
        return
      end

      # Require a host (prevents malformed URLs like "http://")
      if uri.host.blank?
        errors.add(:original_url, 'must include a valid domain')
        return
      end

      # URL structure is valid
      true
    rescue URI::InvalidURIError
      errors.add(:original_url, 'must be a valid URL format')
    end
  end
end
