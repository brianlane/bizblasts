# frozen_string_literal: true

class Integration < ApplicationRecord
  belongs_to :business

  enum :kind, {
    google_calendar: 0,
    zapier: 1,
    webhook: 2
  }

  validates :business_id, presence: true
  validates :kind, presence: true, inclusion: { in: kinds.keys }

  # Store_accessor for config can be added here if specific keys are known
  # e.g., store_accessor :config, :api_key, :webhook_url
end 