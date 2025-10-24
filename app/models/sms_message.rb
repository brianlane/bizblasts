class SmsMessage < ApplicationRecord
  belongs_to :business
  belongs_to :marketing_campaign, optional: true
  belongs_to :tenant_customer
  belongs_to :booking, optional: true

  # ===== PHONE NUMBER ENCRYPTION (Security) =====
  # Phone numbers are PII and must be encrypted at rest for GDPR/CCPA compliance
  # 
  # Implementation:
  # - The database has only 'phone_number_ciphertext' column (text type)
  # - We use alias_attribute to map 'phone_number' to 'phone_number_ciphertext'
  # - ActiveRecord::Encryption with deterministic: true handles encryption/decryption
  # - Deterministic encryption allows for querying (e.g., for_phone scope)
  # 
  # Security: When you assign to phone_number, it's automatically encrypted
  # before being stored in the phone_number_ciphertext column
  alias_attribute :phone_number, :phone_number_ciphertext
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

    # Use the encrypted attribute directly - Rails handles the encryption
    where(phone_number: normalized)
  }
  
  # Factory method for creating SMS messages with encrypted phone numbers
  # This makes encryption explicit for security auditing tools (CodeQL, etc.)
  # 
  # @param plaintext_phone [String] The plaintext phone number (will be normalized and encrypted)
  # @param content [String] The SMS message content
  # @param attributes [Hash] Additional attributes (business_id, tenant_customer_id, etc.)
  # @return [SmsMessage] The created SMS message with encrypted phone number
  def self.create_with_encrypted_phone!(plaintext_phone, content, attributes = {})
    normalized_phone = PhoneNormalizer.normalize(plaintext_phone)
    
    # Security: phone_number is automatically encrypted by ActiveRecord::Encryption
    # via the 'encrypts :phone_number, deterministic: true' declaration above
    # The normalized plaintext is transformed to ciphertext before database storage
    create!(
      attributes.merge(
        phone_number: normalized_phone, # Plaintext input, encrypted by Rails before storage
        content: content
      )
    )
  end
  
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
