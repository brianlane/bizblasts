# frozen_string_literal: true

class EmailMarketingConnection < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)
  belongs_to :business
  has_many :sync_logs, class_name: 'EmailMarketingSyncLog', dependent: :destroy

  # Providers
  enum :provider, {
    mailchimp: 0,
    constant_contact: 1
  }

  # Sync strategies
  enum :sync_strategy, {
    manual: 0,           # Only sync when manually triggered
    auto_on_change: 1,   # Sync when customers are created/updated
    scheduled: 2         # Sync on a schedule (e.g., daily)
  }, prefix: true

  # Validations
  validates :provider, presence: true
  validates :business_id, uniqueness: { scope: :provider, message: 'already has a connection for this provider' }

  # Encrypt sensitive tokens
  encrypts :access_token
  encrypts :refresh_token

  # Scopes
  scope :active, -> { where(active: true) }
  scope :mailchimp_connections, -> { where(provider: :mailchimp) }
  scope :constant_contact_connections, -> { where(provider: :constant_contact) }
  scope :with_valid_tokens, -> { where('token_expires_at IS NULL OR token_expires_at > ?', Time.current) }
  scope :needing_refresh, -> { where('token_expires_at IS NOT NULL AND token_expires_at <= ?', 5.minutes.from_now) }

  # Callbacks
  before_save :set_connected_at, if: -> { active_changed? && active? }

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def token_expiring_soon?
    token_expires_at.present? && token_expires_at <= 5.minutes.from_now
  end

  def connected?
    active? && access_token.present? && !token_expired?
  end

  def provider_name
    case provider
    when 'mailchimp' then 'Mailchimp'
    when 'constant_contact' then 'Constant Contact'
    else provider.to_s.titleize
    end
  end

  def update_tokens!(token_data)
    update!(
      access_token: token_data[:access_token],
      refresh_token: token_data[:refresh_token] || refresh_token,
      token_expires_at: token_data[:expires_at]
    )
  end

  def record_sync!(contacts_synced: 0)
    update!(
      last_synced_at: Time.current,
      total_contacts_synced: (total_contacts_synced || 0) + contacts_synced
    )
  end

  def deactivate!(reason: nil)
    update!(
      active: false,
      config: config.merge('deactivation_reason' => reason, 'deactivated_at' => Time.current.iso8601)
    )
  end

  def sync_service
    @sync_service ||= case provider
                      when 'mailchimp'
                        EmailMarketing::Mailchimp::ContactSyncService.new(self)
                      when 'constant_contact'
                        EmailMarketing::ConstantContact::ContactSyncService.new(self)
                      end
  end

  def api_client
    @api_client ||= case provider
                    when 'mailchimp'
                      EmailMarketing::Mailchimp::Client.new(self)
                    when 'constant_contact'
                      EmailMarketing::ConstantContact::Client.new(self)
                    end
  end

  # Get available lists/audiences from the provider
  def available_lists
    return [] unless connected?

    api_client.get_lists
  rescue StandardError => e
    Rails.logger.error "[EmailMarketingConnection] Failed to fetch lists: #{e.message}"
    []
  end

  private

  def set_connected_at
    self.connected_at ||= Time.current
  end
end
