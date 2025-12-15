# frozen_string_literal: true

module Csv
  class BookingsExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Customer Email', 'Customer Name', 'Service Name',
        'Staff Member', 'Start Time', 'End Time', 'Status',
        'Amount', 'Notes', 'Created At'
      ]
    end

    def row_for(booking)
      [
        booking.id,
        booking.tenant_customer&.email,
        booking.tenant_customer&.full_name,
        booking.service&.name,
        booking.staff_member&.name,
        format_datetime(booking.start_time),
        format_datetime(booking.end_time),
        booking.status,
        format_currency(booking.total_charge),
        booking.notes,
        format_datetime(booking.created_at)
      ]
    end

    def sample_row
      [
        '', 'customer@example.com', 'John Doe', 'Haircut',
        'Jane Smith', '2025-01-15T10:00:00Z', '2025-01-15T11:00:00Z', 'confirmed',
        '50.00', 'First time customer', ''
      ]
    end

    def default_records
      business.bookings
              .includes(:tenant_customer, :service, :staff_member)
              .order(start_time: :desc)
    end

    def export_name
      'bookings'
    end
  end
end
