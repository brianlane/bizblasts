# frozen_string_literal: true

module PhoneNormalizer
  MINIMUM_DIGITS = 7
  DEFAULT_COUNTRY_CODE = '1'

  module_function

  def normalize(raw_phone)
    return nil if raw_phone.blank?

    cleaned = raw_phone.to_s.gsub(/\D/, '')
    return nil if cleaned.blank?

    # Reject phone numbers that are too short to be valid
    # This prevents polluting the database with invalid phone data
    return nil if cleaned.length < MINIMUM_DIGITS

    normalized = cleaned.length == 10 ? DEFAULT_COUNTRY_CODE + cleaned : cleaned
    "+#{normalized}"
  end

  def normalize_collection(raw_numbers)
    Array(raw_numbers).filter_map { |number| normalize(number) }.uniq
  end
end
