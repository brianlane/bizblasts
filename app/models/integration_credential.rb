class IntegrationCredential < ApplicationRecord
  belongs_to :business

  enum :provider, { twilio: 0, mailgun: 1, sendgrid: 2 }

  validates :provider, presence: true
  validates :config, presence: true
end 