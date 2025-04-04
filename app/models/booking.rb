# frozen_string_literal: true

class Booking < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :service
  belongs_to :staff_member
  belongs_to :tenant_customer
  has_many :invoices, dependent: :nullify
  
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :status, presence: true
  
  validate :end_time_after_start_time
  
  enum :status, {
    pending: 0,
    confirmed: 1,
    completed: 2,
    cancelled: 3,
    no_show: 4
  }
  
  scope :upcoming, -> { where('start_time > ?', Time.current).order(start_time: :asc) }
  scope :past, -> { where('end_time < ?', Time.current).order(start_time: :desc) }
  scope :today, -> { where('DATE(start_time) = ?', Date.current).order(start_time: :asc) }
  
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
    %w[business service staff_member tenant_customer invoices]
  end
  
  private
  
  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?
    
    if end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    end
  end
end
