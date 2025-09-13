class SmsMessage < ApplicationRecord
  belongs_to :business
  belongs_to :marketing_campaign, optional: true
  belongs_to :tenant_customer
  belongs_to :booking, optional: true
  
  validates :phone_number, presence: true
  validates :content, presence: true
  validates :status, presence: true
  
  enum :status, {
    pending: 0,
    sent: 1,
    delivered: 2,
    failed: 3
  }
  
  scope :recent, -> { order(created_at: :desc).limit(20) }
  
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
end
