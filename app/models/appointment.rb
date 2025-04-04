# frozen_string_literal: true

class Appointment < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :service
  belongs_to :staff_member
  belongs_to :tenant_customer
  
  validates :business, presence: true
  validates :service, presence: true
  validates :staff_member, presence: true
  validates :tenant_customer, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  validate :end_time_after_start_time
  validate :staff_member_available
  
  enum :status, { 
    pending: 0,
    confirmed: 1,
    completed: 2,
    cancelled: 3,
    no_show: 4
  }
  
  scope :upcoming, -> { where("start_time > ?", Time.current).order(:start_time) }
  scope :past, -> { where("end_time < ?", Time.current).order(start_time: :desc) }
  scope :today, -> { where("DATE(start_time) = ?", Date.current).order(:start_time) }
  scope :this_week, -> { where("start_time BETWEEN ? AND ?", Date.current.beginning_of_week, Date.current.end_of_week) }
  scope :active, -> { where(status: [:pending, :confirmed]) }
  
  private
  
  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?
    
    if end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    end
  end
  
  def staff_member_available
    return if start_time.blank? || !staff_member
    
    unless staff_member.available_at?(start_time)
      errors.add(:start_time, "staff member is not available at this time")
    end
  end
end 