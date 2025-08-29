# frozen_string_literal: true

# Service object to validate and check availability of a desired subdomain.
# Usage:
#   result = SubdomainAvailabilityService.call("mybiz", exclude_business: current_business)
#   result => { available: true/false, message: "..." }
class SubdomainAvailabilityService
  RESERVED_WORDS = %w[www mail ftp admin root api app support help blog shop store manage settings dashboard].freeze
  FORMAT_REGEX = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/.freeze
  LENGTH_RANGE = (3..63).freeze

  Result = Struct.new(:available, :message) do
    def to_h
      { available: available, message: message }
    end
  end

  # @param subdomain [String] requested subdomain (will be downcased & stripped)
  # @param exclude_business [Business, nil] business that should be ignored in uniqueness checks
  # @return [Result]
  def self.call(subdomain, exclude_business: nil)
    new(subdomain, exclude_business).call
  end

  def initialize(subdomain, exclude_business)
    @subdomain = (subdomain || "").downcase.strip
    @exclude_id = exclude_business&.id
  end

  def call
    return Result.new(false, 'Subdomain cannot be blank') if @subdomain.blank?

    unless valid_format?
      return Result.new(false, 'Invalid subdomain format')
    end

    if reserved_word?
      return Result.new(false, 'This subdomain is reserved')
    end

    unless unique?
      return Result.new(false, 'This subdomain is already taken')
    end

    Result.new(true, 'Subdomain is available')
  rescue StandardError => e
    Rails.logger.error("[SUBDOMAIN_AVAILABILITY] #{e.class}: #{e.message}")
    Result.new(false, 'Unable to check availability. Please try again.')
  end

  private

  def valid_format?
    LENGTH_RANGE.cover?(@subdomain.length) && @subdomain.match?(FORMAT_REGEX)
  end

  def reserved_word?
    RESERVED_WORDS.include?(@subdomain)
  end

  def unique?
    scope = Business.where(subdomain: @subdomain).or(Business.where(hostname: @subdomain))
    scope = scope.where.not(id: @exclude_id) if @exclude_id.present?
    !scope.exists?
  end
end
