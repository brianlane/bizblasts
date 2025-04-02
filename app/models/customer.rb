# frozen_string_literal: true

class Customer < ApplicationRecord
  belongs_to :company
  has_many :appointments, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, 
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :company_id, case_sensitive: false }
  # Optional: Add phone validation if needed
  # validates :phone, presence: true # Add specific format validation if required
end
