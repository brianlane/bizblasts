# frozen_string_literal: true

class PolicyVersion < ApplicationRecord
  POLICY_TYPES = %w[terms_of_service privacy_policy acceptable_use_policy return_policy].freeze
  
  validates :policy_type, presence: true, inclusion: { in: POLICY_TYPES }
  validates :version, presence: true, uniqueness: { scope: :policy_type }
  validates :effective_date, presence: true
  
  scope :active, -> { where(active: true) }
  scope :for_policy_type, ->(type) { where(policy_type: type) }
  scope :requiring_notification, -> { where(requires_notification: true) }
  
  def self.current_version(policy_type)
    # Only cache in non-test environments to avoid test interference
    if Rails.env.test?
      for_policy_type(policy_type).active.first
    else
      # Cache the current version for 5 minutes to reduce database queries
      Rails.cache.fetch("current_policy_version_#{policy_type}", expires_in: 5.minutes) do
        for_policy_type(policy_type).active.first
      end
    end
  end
  
  def self.current_versions
    POLICY_TYPES.map { |type| [type, current_version(type)] }.to_h
  end
  
  def activate!
    transaction do
      # Deactivate all other versions of this policy type
      PolicyVersion.where(policy_type: policy_type).update_all(active: false)
      # Activate this version
      update!(active: true)
      
      # Clear the cache for this policy type
      Rails.cache.delete("current_policy_version_#{policy_type}")
      
      # Mark users as requiring acceptance if this requires notification
      if requires_notification?
        mark_users_for_reacceptance
        send_policy_update_notifications
      end
    end
  end
  
  def policy_name
    policy_type.humanize.titleize
  end
  
  def policy_path
    case policy_type
    when 'terms_of_service'
      '/terms'
    when 'privacy_policy'
      '/privacypolicy'
    when 'acceptable_use_policy'
      '/acceptableusepolicy'
    when 'return_policy'
      '/returnpolicy'
    end
  end
  
  def self.ransackable_attributes(auth_object = nil)
    ["active", "change_summary", "content", "created_at", "effective_date", "id", "id_value", "policy_type", "requires_notification", "termly_embed_id", "updated_at", "version"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
  
  private
  
  def mark_users_for_reacceptance
    case policy_type
    when 'privacy_policy'
      # Privacy policy affects everyone - legal requirement under GDPR/CCPA
      User.update_all(requires_policy_acceptance: true)
    when 'terms_of_service'
      # Terms affects both business and client users
      User.update_all(requires_policy_acceptance: true)
    when 'acceptable_use_policy'
      # AUP affects both user types but less critical (dashboard notification sufficient)
      User.update_all(requires_policy_acceptance: true)
    when 'return_policy'
      # Return policy mainly affects business users
      User.where(role: [:manager, :staff]).update_all(requires_policy_acceptance: true)
    end
  end
  
  def send_policy_update_notifications
    # Only send email notifications for privacy policy changes (GDPR/CCPA requirement)
    # and terms of service changes (affects rights)
    return unless policy_type.in?(['privacy_policy', 'terms_of_service'])

    User.find_each do |user|
      PolicyMailer.policy_update_notification(user, [self]).deliver_later(queue: 'mailers')
    end
  end
end 