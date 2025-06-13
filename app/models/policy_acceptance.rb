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
  
  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end

  def self.ransackable_attributes(auth_object = nil)
    ["accepted_at", "created_at", "id", "id_value", "ip_address", "policy_type", "policy_version", "updated_at", "user_agent", "user_id"]
  end

  def self.has_accepted_policy?(user, policy_type, required_version = nil)
    # Only cache in non-test environments to avoid test interference
    if Rails.env.test?
      acceptance = where(user: user, policy_type: policy_type).order(accepted_at: :desc).first
    else
      # Cache policy acceptance status for 15 minutes to reduce database load
      cache_key = "user_#{user.id}_policy_acceptance_#{policy_type}"
      
      acceptance = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
        where(user: user, policy_type: policy_type).order(accepted_at: :desc).first
      end
    end
    
    return false unless acceptance
    
    if required_version
      acceptance.policy_version == required_version
    else
      true
    end
  end
  
  def self.record_acceptance(user, policy_type, version, request = nil)
    acceptance = create!(
      user: user,
      policy_type: policy_type,
      policy_version: version,
      accepted_at: Time.current,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
    
    # Clear the cache for this user and policy type when recording new acceptance
    cache_key = "user_#{user.id}_policy_acceptance_#{policy_type}"
    Rails.cache.delete(cache_key)
    
    acceptance
  end
end 