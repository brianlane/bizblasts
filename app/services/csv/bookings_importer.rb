# frozen_string_literal: true

module Csv
  class BookingsImporter < BaseImporter
    protected

    def required_headers
      %w[customer_email service_name start_time]
    end

    def process_row(row, row_number)
      customer_email = row['customer_email']&.strip&.downcase
      service_name = row['service_name']&.strip
      start_time = parse_datetime(row['start_time'])

      if customer_email.blank?
        add_error(row_number, 'Customer email is required')
        return
      end

      if service_name.blank?
        add_error(row_number, 'Service name is required')
        return
      end

      if start_time.nil?
        add_error(row_number, "Invalid start time: #{row['start_time']}")
        return
      end

      # Find related records
      customer = business.tenant_customers.find_by('LOWER(email) = ?', customer_email)
      unless customer
        add_error(row_number, "Customer not found: #{customer_email}")
        return
      end

      service = business.services.find_by('LOWER(name) = ?', service_name.downcase)
      unless service
        add_error(row_number, "Service not found: #{service_name}")
        return
      end

      # Find staff member if provided
      staff_member = nil
      if row['staff_member'].present?
        staff_name = row['staff_member'].strip
        staff_member = business.staff_members.find_by('LOWER(name) = ?', staff_name.downcase)
        unless staff_member
          add_error(row_number, "Staff member not found: #{staff_name}")
          return
        end
      else
        # Use first available staff member if not specified
        staff_member = business.staff_members.first
        unless staff_member
          add_error(row_number, 'No staff member available for booking')
          return
        end
      end

      # Bookings are create-only (no update matching)
      attributes = build_attributes(row, customer, service, staff_member, start_time)
      booking = business.bookings.new(attributes)

      if booking.save
        import_run.increment_progress!(created: true)
      else
        add_error(row_number, "Create failed: #{booking.errors.full_messages.join(', ')}")
      end
    end

    def build_attributes(row, customer, service, staff_member, start_time)
      duration = service.duration
      end_time = start_time + duration.minutes

      attrs = {
        tenant_customer: customer,
        service: service,
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        amount: service.price,
        status: :pending
      }

      # Optional fields
      attrs[:notes] = row['notes']&.strip if row['notes'].present?

      if row['status'].present?
        status = row['status'].to_s.strip.downcase
        attrs[:status] = status if Booking.statuses.key?(status)
      end

      if row['amount'].present?
        amount = parse_decimal(row['amount'])
        attrs[:amount] = amount if amount
      end

      attrs
    end
  end
end
