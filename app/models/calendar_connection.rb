# frozen_string_literal: true

class CalendarConnection < ApplicationRecord
  acts_as_tenant(:business)
  
  belongs_to :business
  belongs_to :staff_member
  has_many :calendar_event_mappings, dependent: :destroy
  has_many :external_calendar_events, dependent: :destroy
  has_many :bookings, through: :calendar_event_mappings
  
  # Enum for calendar providers
  enum :provider, {
    google: 0,
    microsoft: 1,
    caldav: 2
  }
  
  # Encrypt sensitive OAuth tokens and CalDAV credentials
  encrypts :access_token
  encrypts :refresh_token
  encrypts :caldav_password
  
  validates :business_id, presence: true
  validates :staff_member_id, presence: true
  validates :provider, presence: true
  validates :access_token, presence: true, if: :oauth_provider?
  validates :caldav_username, presence: true, if: :caldav_provider?
  validates :caldav_password, presence: true, if: :caldav_provider?
  validates :active, inclusion: { in: [true, false] }
  
  # Uniqueness constraint per staff member and provider
  validates :provider, uniqueness: { scope: [:business_id, :staff_member_id] }
  
  scope :active, -> { where(active: true) }
  scope :google_connections, -> { where(provider: :google) }
  scope :microsoft_connections, -> { where(provider: :microsoft) }
  scope :caldav_connections, -> { where(provider: :caldav) }
  scope :needs_sync, -> { where('last_synced_at IS NULL OR last_synced_at < ?', 1.hour.ago) }
  
  # Callbacks
  before_create :set_connected_at
  after_create_commit :enqueue_initial_import
  after_create_commit :clear_staff_availability_cache
  after_update_commit :clear_staff_availability_cache, if: :saved_change_to_last_synced_at?
  after_destroy_commit :clear_staff_availability_cache
  before_destroy :remove_default_reference_from_staff_member
  
  def oauth_provider?
    google? || microsoft?
  end
  
  def caldav_provider?
    caldav?
  end
  
  def token_expired?
    return false if token_expires_at.blank?
    token_expires_at <= Time.current
  end
  
  def needs_refresh?
    token_expired? && refresh_token.present?
  end
  
  def provider_display_name
    case provider
    when 'google'
      'Google Calendar'
    when 'microsoft'
      'Microsoft Outlook'
    when 'caldav'
      caldav_provider_display_name
    else
      provider.humanize
    end
  end

  def caldav_provider_display_name
    case caldav_provider
    when 'icloud'
      'iCloud Calendar'
    when 'nextcloud'
      'Nextcloud Calendar'
    when 'generic'
      'CalDAV Calendar'
    else
      'CalDAV Calendar'
    end
  end
  
  def last_sync_status
    return 'Never synced' if last_synced_at.blank?
    return 'Synced recently' if last_synced_at > 1.hour.ago
    return 'Sync overdue' if last_synced_at < 6.hours.ago
    'Needs sync'
  end
  
  def sync_scopes
    return [] if scopes.blank?
    scopes.split(',').map(&:strip)
  end
  
  def sync_scopes=(scope_array)
    self.scopes = Array(scope_array).join(',')
  end
  
  # Mark connection as synced
  def mark_synced!
    update!(last_synced_at: Time.current)
    # Run cache clear immediately so callers in the same transaction see fresh data
    clear_staff_availability_cache
  end
  
  # Deactivate connection (e.g., after revocation)
  def deactivate!
    update!(active: false)
  end
  
  # Check if connection has required calendar permissions
  def has_calendar_permissions?
    case provider
    when 'google'
      # OAuth providers require scopes
      return false if scopes.blank?
      # Use exact match instead of .include?() to prevent substring injection attacks
      # OAuth scopes must match exactly, not just contain the string
      sync_scopes.any? { |scope| scope == 'https://www.googleapis.com/auth/calendar' }
    when 'microsoft'
      # OAuth providers require scopes
      return false if scopes.blank?
      sync_scopes.any? { |scope| scope.include?('Calendars') }
    when 'caldav'
      true # CalDAV doesn't use OAuth scopes
    else
      false
    end
  end
  
  # --------------------------------------------------------------------------
  # Callback helpers
  # --------------------------------------------------------------------------
  def remove_default_reference_from_staff_member
    return unless staff_member&.default_calendar_connection_id == id

    # Skip validations to avoid potential circular dependency or validation failures
    staff_member.update_column(:default_calendar_connection_id, nil)
  end

  private
  
  def set_connected_at
    self.connected_at ||= Time.current
  end

  # Enqueue an initial availability import so the connection begins syncing immediately
  def enqueue_initial_import
    return unless active? && staff_member_id.present?

    Calendar::ImportAvailabilityJob.perform_later(staff_member_id)
  end

  # Clear cached availability when a connection is removed so blocked slots are freed immediately
  def clear_staff_availability_cache
    AvailabilityService.clear_staff_availability_cache(staff_member)
    # Bump timestamp so versioned cache keys change even if store doesn't support delete_matched
    staff_member.touch
  end
end