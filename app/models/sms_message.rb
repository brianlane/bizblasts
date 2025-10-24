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
    normalized = PhoneNormalizer.normalize(plain_phone)
    return none if normalized.blank?

    type = attribute_types["phone_number"]
    ciphertext = type.serialize(normalized) if type.respond_to?(:serialize)
    return none if ciphertext.blank?

    where(phone_number_ciphertext: ciphertext)
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
    update_columns(
      status: self.class.statuses[:delivered],
      delivered_at: Time.current,
      updated_at: Time.current
    )
  end
  
  def mark_as_failed!(error_message)
    update_columns(
      status: self.class.statuses[:failed],
      error_message: error_message,
      updated_at: Time.current
    )
  end
  
  private
  
  def normalize_phone_number
    self.phone_number = PhoneNormalizer.normalize(phone_number)
  end
end
