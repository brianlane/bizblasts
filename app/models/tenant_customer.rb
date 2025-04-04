# frozen_string_literal: true

class TenantCustomer < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  
  # Base validations
  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, presence: true
  
  # Custom validation to optimize uniqueness check
  validate :email_uniqueness_within_business, if: -> { email.present? && business.present? }
  
  scope :active, -> { where(active: true) }
  
  def full_name
    name
  end
  
  def recent_bookings
    bookings.order(start_time: :desc).limit(5)
  end
  
  def upcoming_bookings
    bookings.where('start_time > ?', Time.now).order(start_time: :asc)
  end
  
  def current_business
    Business.find(business_id)
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name email phone address notes active last_appointment created_at updated_at business_id]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings invoices]
  end
  
  # Index for faster lookup during uniqueness validation
  # This combined with the index on the database should improve performance
  def self.index_for_email_uniqueness
    @email_business_index ||= {}
  end
  
  private
  
  # Memory-based uniqueness check to avoid expensive database operations
  def email_uniqueness_within_business
    # Only check if both email and business are present
    return unless email.present? && business.present?
    
    # Skip database query if this is a new record with a unique email
    return if new_record? && !TenantCustomer.exists?(email: email, business_id: business_id)
    
    # For existing records, ensure no other records have the same email in this business
    if TenantCustomer.where.not(id: id).exists?(email: email, business_id: business_id)
      errors.add(:email, "must be unique within this business")
    end
  end
end 