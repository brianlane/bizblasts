# frozen_string_literal: true

# Concern for handling booking scopes
module BookingScopes
  extend ActiveSupport::Concern

  included do
    # Common scopes for filtering bookings
    scope :upcoming, -> { where('start_time > ?', Time.current).where.not(status: :cancelled).order(start_time: :asc) }
    scope :past, -> { where('end_time < ?', Time.current).order(start_time: :desc) }
    scope :today, -> {
      # Use Rails time zone (UTC by default) to match stored timestamps
      where(start_time: Time.current.beginning_of_day..Time.current.end_of_day)
        .order(start_time: :asc)
    }
    scope :on_date, ->(date) { where(start_time: date.all_day) }
    scope :for_staff, ->(staff_member_id) { where(staff_member_id: staff_member_id) }
    scope :for_customer, ->(customer_id) { where(tenant_customer_id: customer_id) }
    scope :by_status, ->(status) { where(status: status) if status.present? }
    scope :by_email, ->(email) { joins(:tenant_customer).where(tenant_customers: { email: email }) if email.present? }
  end
end 