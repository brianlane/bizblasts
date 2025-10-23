class SmsMessage < ApplicationRecord
  belongs_to :business
  belongs_to :marketing_campaign, optional: true
  belongs_to :tenant_customer
  belongs_to :booking, optional: true

  # Encrypt phone numbers with deterministic encryption to allow querying
  encrypts :phone_number, deterministic: true

  validates :phone_number, presence: true
  validates :content, presence: true
  validates :status, presence: true
  
  before_validation :normalize_phone_number
  
  enum :status, {
    pending: 0,
    sent: 1,
    delivered: 2,
    failed: 3
  }
  
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # Lookup by plain phone number using deterministic encryption
  scope :for_phone, ->(plain_phone) {
    return none if plain_phone.blank?
    where(phone_number: plain_phone)
  }
  
  def deliver
    SmsNotificationJob.perform_later(phone_number, content, { 
      booking_id: booking_id,
      tenant_customer_id: tenant_customer_id,
      marketing_campaign_id: marketing_campaign_id
    })
  end
  
  def mark_as_sent!
    update(status: :sent, sent_at: Time.current)
  end
  
  def mark_as_delivered!
    update(status: :delivered, delivered_at: Time.current)
  end
  
  def mark_as_failed!(error_message)
    update(status: :failed, error_message: error_message)
  end
  
  private
  
  def normalize_phone_number
    return if phone_number.blank?
    
    # Normalize phone to E.164 format (+1XXXXXXXXXX)
    cleaned = phone_number.gsub(/\D/, '')
    return if cleaned.length < 7  # Too short to be valid
    
    # Add country code if missing
    cleaned = "1#{cleaned}" if cleaned.length == 10
    self.phone_number = "+#{cleaned}"
  end
end
