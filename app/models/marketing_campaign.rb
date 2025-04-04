class MarketingCampaign < ApplicationRecord
  include TenantScoped
  
  has_many :sms_messages, dependent: :destroy
  
  validates :name, presence: true
  validates :campaign_type, presence: true
  validates :status, presence: true
  validates :scheduled_at, presence: true
  
  enum :campaign_type, {
    email: 0,
    sms: 1,
    combined: 2
  }
  
  enum :status, {
    draft: 0,
    scheduled: 1,
    running: 2,
    completed: 3,
    cancelled: 4
  }
  
  scope :active, -> { where(status: [:scheduled, :running]) }
  scope :recent, -> { order(created_at: :desc).limit(10) }
  
  def execute!
    update(status: :running, started_at: Time.current)
    MarketingCampaignJob.perform_later(id)
  end
  
  def complete!
    update(status: :completed, completed_at: Time.current)
  end
  
  def cancel!
    update(status: :cancelled)
  end
end
