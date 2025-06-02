# frozen_string_literal: true

class TenantCustomer < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :payments, dependent: :destroy
  
  # Allow access to User accounts associated with this customer's business
  has_many :users, through: :business, source: :clients
  
  # Base validations
  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :business_id, message: "must be unique within this business" }
  # Make phone optional for now to fix booking flow
  validates :phone, presence: true, allow_blank: true
  
  # Callbacks
  after_create :send_business_customer_notification
  
  # Add accessor to skip email notifications when handled by staggered delivery
  attr_accessor :skip_notification_email
  
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
    %w[id name email phone address notes active last_booking created_at updated_at business_id]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings invoices orders]
  end
  
  # Index for faster lookup during uniqueness validation
  # This combined with the index on the database should improve performance
  def self.index_for_email_uniqueness
    @email_business_index ||= {}
  end
  
  private
  
  def send_business_customer_notification
    # Skip if explicitly disabled (used by staggered email service)
    return if skip_notification_email
    
    begin
      BusinessMailer.new_customer_notification(self).deliver_later
      Rails.logger.info "[EMAIL] Scheduled business customer notification for Customer #{name} (#{email})"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule business customer notification for Customer #{name} (#{email}): #{e.message}"
    end
  end
end 