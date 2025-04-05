# frozen_string_literal: true

class StaffMember < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :user, optional: true
  has_many :bookings
  has_and_belongs_to_many :services
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :active, inclusion: { in: [true, false] }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, presence: true
  
  scope :active, -> { where(active: true) }
  
  def available_services
    services.where(active: true)
  end
  
  def upcoming_bookings
    bookings.upcoming
  end
  
  def today_bookings
    bookings.today
  end
  
  def calendar_data
    bookings.upcoming.map do |booking|
      {
        id: booking.id,
        title: booking.tenant_customer.name,
        start: booking.start_time,
        end: booking.end_time,
        status: booking.status
      }
    end
  end
  
  # availability is stored as: { "monday" => ["09:00-12:00", "13:00-17:00"], ... }
  # Method to check if staff member is available for a given time *duration*
  def available?(start_time, end_time)
    return false unless active? && start_time && end_time && end_time > start_time

    day_of_week = start_time.strftime('%A').downcase
    intervals_for_day = availability&.dig(day_of_week)
    return false unless intervals_for_day.present?

    available_ranges = intervals_for_day.map do |interval_data|
      start_str = nil
      end_str = nil
      if interval_data.is_a?(String)
        # Handle "HH:MM-HH:MM" format
        start_str, end_str = interval_data.split('-')
      elsif interval_data.is_a?(Hash)
        # Handle {start: "HH:MM", end: "HH:MM"} format (symbol or string keys)
        start_str = interval_data[:start] || interval_data["start"]
        end_str = interval_data[:end] || interval_data["end"]
      end
      
      # Skip if format is unrecognized or strings are missing
      next unless start_str && end_str 

      begin
        start_tod = Tod::TimeOfDay.parse(start_str)
        end_tod = Tod::TimeOfDay.parse(end_str)
        start_tod...end_tod
      rescue ArgumentError
        nil # Ignore intervals that can't be parsed
      end
    end.compact # Remove nil entries from map

    # Return false if no valid ranges were found for the day
    return false if available_ranges.empty?

    # Check for overlapping bookings for this staff member during the requested time
    has_overlapping_booking = Booking
                                .where(staff_member: self)
                                .where.not(status: :cancelled)
                                .where("start_time < ? AND end_time > ?", end_time, start_time)
                                .exists?

    return false if has_overlapping_booking

    # If all checks pass, the slot is available
    true
  end
  
  # Check if staff member is generally available at a specific point in time 
  # based on their defined working hours for that day.
  # Does NOT check against existing bookings.
  def available_at?(time)
    return false unless active? && time

    day_of_week = time.strftime('%A').downcase
    date_str = time.strftime('%Y-%m-%d')
    av_hash = self.availability # Read the attribute

    # Check for exceptions first for the specific date
    intervals_for_day = av_hash&.dig('exceptions', date_str)
    
    # If no exception for the date, use the regular day schedule
    intervals_for_day ||= av_hash&.dig(day_of_week)
    
    return false unless intervals_for_day.present?

    time_of_day = Tod::TimeOfDay.new(time.hour, time.min, time.sec)

    available_ranges = intervals_for_day.map do |interval_data|
      start_str = nil
      end_str = nil
      if interval_data.is_a?(String)
        start_str, end_str = interval_data.split('-')
      elsif interval_data.is_a?(Hash)
        start_str = interval_data[:start] || interval_data["start"]
        end_str = interval_data[:end] || interval_data["end"]
      end
      next unless start_str && end_str
      begin
        start_tod = Tod::TimeOfDay.parse(start_str)
        end_tod = Tod::TimeOfDay.parse(end_str)
        start_tod...end_tod
      rescue ArgumentError
        nil
      end
    end.compact

    return false if available_ranges.empty?

    available_ranges.any? { |range| range.cover?(time_of_day) }
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name email phone bio active business_id created_at updated_at]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings services]
  end
  
  private
  
  # Remove check_time_in_intervals as logic is moved into available_at?
  # def check_time_in_intervals(time_of_day, intervals)
  #   ...
  # end
end
