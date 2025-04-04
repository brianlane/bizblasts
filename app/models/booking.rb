# frozen_string_literal: true

class Booking < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :service
  belongs_to :staff_member
  belongs_to :tenant_customer
  belongs_to :promotion, optional: true
  has_one :invoice, dependent: :nullify
  
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :status, presence: true
  validate :end_time_after_start_time
  validate :no_overlapping_bookings, on: :create
  validates :original_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  enum :status, {
    pending: 0,
    confirmed: 1,
    cancelled: 2,
    completed: 3,
    no_show: 4
  }
  
  scope :upcoming, -> { where('start_time > ?', Time.current).where.not(status: :cancelled).order(start_time: :asc) }
  scope :past, -> { where('end_time < ?', Time.current).order(start_time: :desc) }
  scope :today, -> { where('DATE(start_time) = ?', Date.current).order(start_time: :asc) }
  scope :on_date, ->(date) { where(start_time: date.all_day) }
  scope :for_staff, ->(staff_member_id) { where(staff_member_id: staff_member_id) }
  scope :for_customer, ->(customer_id) { where(tenant_customer_id: customer_id) }
  
  delegate :name, to: :service, prefix: true, allow_nil: true
  delegate :name, to: :staff_member, prefix: true, allow_nil: true
  delegate :name, :email, to: :tenant_customer, prefix: :customer, allow_nil: true
  
  def duration
    (end_time - start_time) / 60 # in minutes
  end
  
  def cancel!
    update(status: :cancelled)
    # More cancellation logic would go here
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id start_time end_time status notes service_id staff_member_id tenant_customer_id 
       business_id created_at updated_at]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business service staff_member tenant_customer invoice promotion]
  end
  
  private
  
  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?
    
    if end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    end
  end
  
  def no_overlapping_bookings
    return if start_time.blank? || end_time.blank? || staff_member_id.blank?
    
    overlapping = Booking
                    .where(staff_member_id: staff_member_id)
                    .where.not(status: :cancelled)
                    .where.not(id: id)
                    .where("start_time < ? AND end_time > ?", end_time, start_time)
    
    if overlapping.exists?
      errors.add(:base, "Booking conflicts with another existing booking for this staff member")
    end
  end
end
