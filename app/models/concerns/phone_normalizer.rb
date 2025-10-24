# frozen_string_literal: true

module PhoneNormalizer
  MINIMUM_DIGITS = 7
  DEFAULT_COUNTRY_CODE = '1'

  module_function

  def normalize(raw_phone)
    return if raw_phone.blank?

    cleaned = raw_phone.gsub(/\D/, '')
    return if cleaned.length < MINIMUM_DIGITS

    normalized = cleaned.length == 10 ? DEFAULT_COUNTRY_CODE + cleaned : cleaned
    "+#{normalized}"
  end

  def normalize_collection(raw_numbers)
    Array(raw_numbers).filter_map { |number| normalize(number) }.uniq
  end
end
