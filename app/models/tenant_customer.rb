# frozen_string_literal: true

class TenantCustomer < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :orders, dependent: :destroy
  
  # Base validations
  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :business_id, message: "must be unique within this business" }
  # Make phone optional for now to fix booking flow
  validates :phone, presence: true, allow_blank: true
  
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
end 