class NotificationTemplate < ApplicationRecord
  belongs_to :business

  enum :channel, { email: 0, sms: 1 }

  validates :event_type, presence: true
  validates :channel, presence: true
  validates :subject, presence: true
  validates :body, presence: true
end 