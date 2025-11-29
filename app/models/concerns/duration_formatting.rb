# frozen_string_literal: true

# Provides duration formatting helpers for converting minutes to human-readable strings
module DurationFormatting
  extend ActiveSupport::Concern

  # Convert minutes to a human-readable duration string
  #
  # @param minutes [Integer, Float] the duration in minutes
  # @return [String] formatted duration (e.g., "30 mins", "2 hours", "3 days")
  #
  # @example
  #   duration_in_words(30)   #=> "30 mins"
  #   duration_in_words(90)   #=> "1.5 hours"
  #   duration_in_words(120)  #=> "2 hours"
  #   duration_in_words(1440) #=> "1 day"
  #   duration_in_words(2880) #=> "2 days"
  def duration_in_words(minutes)
    return "0 mins" if minutes.to_i.zero?

    if minutes < 60
      "#{minutes} min#{'s' if minutes != 1}"
    elsif minutes < 1440
      hours = (minutes / 60.0).round(1)
      hours == hours.to_i ? "#{hours.to_i} hour#{'s' if hours.to_i != 1}" : "#{hours} hours"
    else
      days = (minutes / 1440.0).round(1)
      days == days.to_i ? "#{days.to_i} day#{'s' if days.to_i != 1}" : "#{days} days"
    end
  end
end
