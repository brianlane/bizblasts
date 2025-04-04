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
    
    day_of_week = time.strftime('%A').downcase.to_sym
    current_tod = Tod::TimeOfDay.new(time.hour, time.min) 

    applicable_intervals = []
    # Check exceptions first 
    date_str = time.strftime('%Y-%m-%d')
    
    # --> New Debugging <--
    av_hash = self.availability # Read the attribute
    puts "[DEBUG available_at?] Availability Hash: #{av_hash.inspect}" 
    puts "[DEBUG available_at?] Availability Keys: #{av_hash&.keys.inspect}" 
    # --> End Debugging <--
    
    if av_hash&.dig('exceptions', date_str) # Use string key for 'exceptions'
      applicable_intervals = av_hash['exceptions'][date_str]
    else
      # Check regular schedule
      applicable_intervals = av_hash&.dig(day_of_week.to_s) # Use string key for day_of_week
    end

    return false if applicable_intervals.blank?

    # Pre-process intervals into Tod objects
    parsed_intervals = applicable_intervals.map do |interval|
      begin
        start_str = interval[:start] || interval["start"]
        end_str = interval[:end] || interval["end"]
        start_tod = Tod::TimeOfDay.parse(start_str)
        end_tod = Tod::TimeOfDay.parse(end_str)
        start_tod...end_tod # Create a Range of Tod::TimeOfDay
      rescue ArgumentError => e
        nil
      end
    end.compact
    
    # Check if the current time falls within any of the valid ranges
    parsed_intervals.any? { |range| range.cover?(current_tod) }
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
