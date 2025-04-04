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
  
  def available_at?(time)
    return false unless active?
    
    # Get the day of week and normalize to symbol
    day_of_week = time.strftime('%A').downcase.to_sym
    
    # Check exceptions first (specific dates override regular schedule)
    date_str = time.strftime('%Y-%m-%d')
    if availability&.dig(:exceptions, date_str)
      return check_time_in_intervals(time, availability[:exceptions][date_str])
    end
    
    # Check regular schedule for that day
    return false unless availability&.dig(day_of_week)
    
    check_time_in_intervals(time, availability[day_of_week])
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
  
  def check_time_in_intervals(time, intervals)
    # No intervals means not available
    return false if intervals.blank?
    
    # Convert time to minutes since midnight for easier comparison
    minutes = time.hour * 60 + time.min
    
    # Check each interval
    intervals.any? do |interval|
      start_time = parse_time_to_minutes(interval[:start] || interval["start"])
      end_time = parse_time_to_minutes(interval[:end] || interval["end"])
      
      # Time is in range if >= start and < end
      start_time && end_time && minutes >= start_time && minutes < end_time
    end
  end
  
  def parse_time_to_minutes(time_str)
    return nil unless time_str.is_a?(String) && time_str.match?(/^\d{1,2}:\d{2}$/)
    
    hours, minutes = time_str.split(':').map(&:to_i)
    hours * 60 + minutes
  end
end
