# frozen_string_literal: true

class VideoMeetingConnection < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :staff_member

  # Provider types for video meetings
  enum :provider, { zoom: 0, google_meet: 1 }

  # Encrypt sensitive tokens
  encrypts :access_token
  encrypts :refresh_token

  # Validations
  validates :business_id, presence: true
  validates :staff_member_id, presence: true
  validates :provider, presence: true
  validates :access_token, presence: true
  validates :provider, uniqueness: {
    scope: [:business_id, :staff_member_id],
    message: "connection already exists for this staff member"
  }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :zoom_connections, -> { where(provider: :zoom) }
  scope :google_meet_connections, -> { where(provider: :google_meet) }
  scope :for_staff_member, ->(staff_member_id) { where(staff_member_id: staff_member_id) }

  # Check if token has expired
  def token_expired?
    return false if token_expires_at.blank?
    token_expires_at <= Time.current
  end

  # Check if token needs refresh
  def needs_refresh?
    token_expired? && refresh_token.present?
  end

  # Check if token will expire soon (within 5 minutes)
  def token_expiring_soon?
    return false if token_expires_at.blank?
    token_expires_at <= 5.minutes.from_now
  end

  # Deactivate the connection
  def deactivate!
    update!(active: false)
  end

  # Reactivate the connection
  def activate!
    update!(active: true)
  end

  # Mark connection as recently used
  def mark_used!
    update!(last_used_at: Time.current)
  end

  # Update tokens after refresh
  def update_tokens!(access_token:, refresh_token: nil, expires_at: nil)
    attrs = { access_token: access_token }
    attrs[:refresh_token] = refresh_token if refresh_token.present?
    attrs[:token_expires_at] = expires_at if expires_at.present?
    update!(attrs)
  end

  # Human-readable provider name
  def provider_name
    case provider
    when 'zoom' then 'Zoom'
    when 'google_meet' then 'Google Meet'
    else provider.humanize
    end
  end

  # Create a Google Meet connection from an existing Google Calendar connection
  # This allows reusing the same OAuth tokens without requiring a separate auth flow
  def self.create_from_calendar_connection!(calendar_connection)
    raise ArgumentError, "Only Google calendar connections can be converted" unless calendar_connection.provider == 'google'

    # Check if Google Meet connection already exists for this staff member
    existing = where(
      business_id: calendar_connection.business_id,
      staff_member_id: calendar_connection.staff_member_id,
      provider: :google_meet
    ).first

    if existing
      # Update existing connection with fresh tokens
      existing.update!(
        access_token: calendar_connection.access_token,
        refresh_token: calendar_connection.refresh_token,
        token_expires_at: calendar_connection.token_expires_at,
        uid: calendar_connection.uid,
        scopes: calendar_connection.scopes,
        active: true,
        connected_at: Time.current
      )
      existing
    else
      # Create new connection from calendar tokens
      create!(
        business_id: calendar_connection.business_id,
        staff_member_id: calendar_connection.staff_member_id,
        provider: :google_meet,
        access_token: calendar_connection.access_token,
        refresh_token: calendar_connection.refresh_token,
        token_expires_at: calendar_connection.token_expires_at,
        uid: calendar_connection.uid,
        scopes: calendar_connection.scopes,
        active: true,
        connected_at: Time.current
      )
    end
  end

  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id staff_member_id provider uid active connected_at last_used_at created_at updated_at]
  end

  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business staff_member]
  end
end
