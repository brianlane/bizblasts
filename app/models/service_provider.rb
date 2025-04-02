# frozen_string_literal: true

class ServiceProvider < ApplicationRecord
  belongs_to :company
  has_many :appointments, dependent: :restrict_with_error # Prevent deleting if appointments exist

  validates :company, presence: true
  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :active, inclusion: { in: [true, false] }
  # Optional validations for email and phone
  # validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  # validates :phone, format: { with: /\A\+?\d{1,3}[-.\s]?\(?\d{1,3}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}\z/, message: "must be a valid phone number" }, allow_blank: true

  # We might need logic here related to availability JSON if used actively
end 