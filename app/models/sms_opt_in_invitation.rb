class SmsOptInInvitation < ApplicationRecord
  belongs_to :business
  belongs_to :tenant_customer, optional: true

  validates :phone_number, presence: true, format: { with: /\A\+?[1-9]\d{1,14}\z/ }
  validates :context, presence: true
  validates :sent_at, presence: true

  # Scopes for common queries
  scope :recent, ->(days = 30) { where('sent_at > ?', days.days.ago) }
  scope :responded, -> { where.not(responded_at: nil) }
  scope :successful, -> { where(successful_opt_in: true) }
  scope :for_phone_and_business, ->(phone, business_id) { where(phone_number: phone, business_id: business_id) }

  # Check if an invitation was recently sent (30-day rule)
  def self.recent_invitation_sent?(phone_number, business_id, days = 30)
    for_phone_and_business(phone_number, business_id)
      .recent(days)
      .exists?
  end

  # Record a response to an invitation
  def record_response!(response_text)
    update!(
      responded_at: Time.current,
      response: response_text,
      successful_opt_in: opt_in_response?(response_text)
    )
  end

  # Check if response indicates successful opt-in
  def self.opt_in_response?(response_text)
    return false unless response_text.present?

    opt_in_keywords = %w[YES START SUBSCRIBE Y]
    opt_in_keywords.include?(response_text.strip.upcase)
  end

  def opt_in_response?(response_text)
    self.class.opt_in_response?(response_text)
  end

  # Analytics methods
  def self.conversion_rate(days = 30)
    recent_invitations = recent(days)
    return 0 if recent_invitations.count == 0

    successful_count = recent_invitations.successful.count
    (successful_count.to_f / recent_invitations.count * 100).round(2)
  end

  def self.response_rate(days = 30)
    recent_invitations = recent(days)
    return 0 if recent_invitations.count == 0

    responded_count = recent_invitations.responded.count
    (responded_count.to_f / recent_invitations.count * 100).round(2)
  end
end