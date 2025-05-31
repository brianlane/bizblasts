# frozen_string_literal: true

class PolicyAcceptance < ApplicationRecord
  belongs_to :user
  
  POLICY_TYPES = %w[terms_of_service privacy_policy acceptable_use_policy return_policy].freeze
  
  validates :policy_type, presence: true, inclusion: { in: POLICY_TYPES }
  validates :policy_version, presence: true
  validates :accepted_at, presence: true
  
  scope :for_user, ->(user) { where(user: user) }
  scope :for_policy_type, ->(type) { where(policy_type: type) }
  scope :latest_for_user, ->(user) {
    where(user: user).order(accepted_at: :desc)
  }
  
  def self.has_accepted_policy?(user, policy_type, required_version = nil)
    acceptance = where(user: user, policy_type: policy_type).order(accepted_at: :desc).first
    return false unless acceptance
    
    if required_version
      acceptance.policy_version == required_version
    else
      true
    end
  end
  
  def self.record_acceptance(user, policy_type, version, request = nil)
    create!(
      user: user,
      policy_type: policy_type,
      policy_version: version,
      accepted_at: Time.current,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  end
end 