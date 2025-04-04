# frozen_string_literal: true

class Customer < ApplicationRecord
  include TenantScoped
  
  belongs_to :company
  has_many :appointments, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :payments, dependent: :restrict_with_error
  has_many :promotion_redemptions, dependent: :destroy
  has_many :promotions, through: :promotion_redemptions
  
  validates :name, presence: true
  validates :email, presence: true, 
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :company_id, case_sensitive: false }
  validates :phone, presence: true
  # Optional: Add phone validation if needed
  # validates :phone, presence: true # Add specific format validation if required
  
  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc).limit(10) }
  
  def upcoming_bookings
    bookings.upcoming
  end
  
  def upcoming_appointments
    appointments.upcoming
  end
  
  def past_bookings
    bookings.past
  end
  
  def past_appointments
    appointments.past
  end
  
  def total_spent
    payments.successful.sum(:amount)
  end
  
  def send_reminder(booking)
    BookingReminderJob.perform_later(booking.id)
  end
end
