# frozen_string_literal: true

class QuickbooksConnection < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :business

  encrypts :access_token
  encrypts :refresh_token

  validates :business_id, presence: true
  validates :realm_id, presence: true
  validates :environment, presence: true
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  def token_expired?
    return false if token_expires_at.blank?
    token_expires_at <= Time.current
  end

  def needs_refresh?
    token_expired? && refresh_token.present?
  end

  def mark_used!
    update!(last_used_at: Time.current)
  end

  def deactivate!
    update!(active: false)
  end
end
