# frozen_string_literal: true

module Csv
  class CustomersExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Email', 'First Name', 'Last Name', 'Phone',
        'Address', 'Notes', 'Active', 'Phone Opt-In',
        'Email Marketing Opt-Out', 'Created At', 'Last Booking'
      ]
    end

    def row_for(customer)
      [
        customer.id,
        customer.email,
        customer.first_name,
        customer.last_name,
        customer.phone,
        customer.address,
        customer.notes,
        format_boolean(customer.active),
        format_boolean(customer.phone_opt_in),
        format_boolean(customer.email_marketing_opt_out),
        format_datetime(customer.created_at),
        format_datetime(customer.last_appointment)
      ]
    end

    def sample_row
      [
        '', 'customer@example.com', 'John', 'Doe', '+1234567890',
        '123 Main St', 'Regular customer', 'true', 'false',
        'false', '', ''
      ]
    end

    def default_records
      business.tenant_customers.order(:created_at)
    end

    def export_name
      'customers'
    end
  end
end
