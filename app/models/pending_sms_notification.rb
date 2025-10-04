class PendingSmsNotification < ApplicationRecord
  # Associations
  belongs_to :business
  belongs_to :tenant_customer
  belongs_to :booking, optional: true
  belongs_to :invoice, optional: true
  belongs_to :order, optional: true

  # Validations
  validates :notification_type, presence: true
  validates :sms_type, presence: true
  validates :template_data, presence: true
  validates :phone_number, presence: true, format: { with: /\A\+?[1-9]\d{1,14}\z/ }
  validates :queued_at, presence: true
  validates :expires_at, presence: true
  validates :deduplication_key, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[pending sent failed expired] }

  # Status enum (for better querying)
  enum :status, {
    pending: 'pending',
    sent: 'sent',
    failed: 'failed',
    expired: 'expired'
  }

  # Scopes for common queries
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :not_expired, -> { where('expires_at >= ?', Time.current) }
  scope :for_customer, ->(customer) { where(tenant_customer: customer) }
  scope :for_business, ->(business) { where(business: business) }
  scope :for_notification_type, ->(type) { where(notification_type: type) }
  scope :ready_for_processing, -> { pending.not_expired.order(:queued_at) }

  # Class methods for creating notifications
  def self.queue_notification(notification_type:, customer:, business:, sms_type:, template_data:, **associations)
    # Generate deduplication key to prevent duplicate queuing
    dedup_key = generate_deduplication_key(
      notification_type: notification_type,
      customer_id: customer.id,
      business_id: business.id,
      associations: associations
    )

    # Check if this notification is already queued
    existing = find_by(deduplication_key: dedup_key)
    if existing&.pending?
      Rails.logger.info "[PENDING_SMS] Notification already queued: #{dedup_key}"
      return existing
    end

    # Create new pending notification
    notification = create!(
      business: business,
      tenant_customer: customer,
      notification_type: notification_type.to_s,
      sms_type: sms_type.to_s,
      template_data: template_data,
      phone_number: customer.phone,
      queued_at: Time.current,
      expires_at: 7.days.from_now, # Auto-expire after 7 days
      deduplication_key: dedup_key,
      status: 'pending',
      **associations.slice(:booking, :invoice, :order)
    )

    Rails.logger.info "[PENDING_SMS] Queued #{notification_type} for customer #{customer.id} (business #{business.id})"
    notification
  rescue ActiveRecord::RecordNotUnique
    # Handle race condition where duplicate was created between check and create
    find_by!(deduplication_key: dedup_key)
  end

  # Queue booking-related notifications
  def self.queue_booking_notification(notification_type, booking, template_data)
    queue_notification(
      notification_type: notification_type,
      customer: booking.tenant_customer,
      business: booking.business,
      sms_type: 'booking',
      template_data: template_data,
      booking: booking
    )
  end

  # Queue invoice-related notifications
  def self.queue_invoice_notification(notification_type, invoice, template_data)
    queue_notification(
      notification_type: notification_type,
      customer: invoice.tenant_customer,
      business: invoice.business,
      sms_type: 'payment',
      template_data: template_data,
      invoice: invoice
    )
  end

  # Queue order-related notifications
  def self.queue_order_notification(notification_type, order, template_data)
    queue_notification(
      notification_type: notification_type,
      customer: order.tenant_customer,
      business: order.business,
      sms_type: 'order',
      template_data: template_data,
      order: order
    )
  end

  # Mark notification as sent
  def mark_as_sent!
    update!(
      status: 'sent',
      processed_at: Time.current,
      failed_at: nil,
      failure_reason: nil
    )
    Rails.logger.info "[PENDING_SMS] Marked notification #{id} as sent"
  end

  # Mark notification as failed
  def mark_as_failed!(reason)
    update!(
      status: 'failed',
      failed_at: Time.current,
      failure_reason: reason
    )
    Rails.logger.error "[PENDING_SMS] Marked notification #{id} as failed: #{reason}"
  end

  # Mark notification as expired
  def mark_as_expired!
    update!(status: 'expired')
    Rails.logger.info "[PENDING_SMS] Marked notification #{id} as expired"
  end

  # Check if notification is expired
  def expired?
    expires_at < Time.current
  end

  # Get notification age in days
  def age_in_days
    (Time.current - queued_at) / 1.day
  end

  # Clean up expired notifications
  def self.cleanup_expired!
    expired_count = expired.update_all(status: 'expired')
    Rails.logger.info "[PENDING_SMS] Marked #{expired_count} notifications as expired" if expired_count > 0
    expired_count
  end

  # Get statistics for monitoring
  def self.stats
    {
      pending: pending.count,
      expired: expired.count,
      total: count,
      oldest_pending: pending.minimum(:queued_at),
      newest_pending: pending.maximum(:queued_at)
    }
  end

  private

  # Generate unique deduplication key
  def self.generate_deduplication_key(notification_type:, customer_id:, business_id:, associations:)
    # Include relevant association IDs in the key
    association_part = associations.compact.map { |k, v| "#{k}:#{v.id}" }.sort.join("|")

    base_key = "#{notification_type}:#{business_id}:#{customer_id}"
    base_key += ":#{association_part}" if association_part.present?

    # Add timestamp component to allow re-queuing after reasonable time (24 hours)
    time_bucket = (Time.current.to_i / 24.hours).to_i
    "#{base_key}:#{time_bucket}"
  end
end