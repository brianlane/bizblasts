# frozen_string_literal: true

module Csv
  class OrdersImporter < BaseImporter
    protected

    def required_headers
      %w[customer_email total_amount]
    end

    def process_row(row, row_number)
      customer_email = row['customer_email']&.strip&.downcase
      total_amount = parse_decimal(row['total_amount'])

      if customer_email.blank?
        add_error(row_number, 'Customer email is required')
        return
      end

      if total_amount.nil? || total_amount < 0
        add_error(row_number, "Invalid total amount: #{row['total_amount']}")
        return
      end

      # Find customer
      customer = business.tenant_customers.find_by('LOWER(email) = ?', customer_email)
      unless customer
        add_error(row_number, "Customer not found: #{customer_email}")
        return
      end

      # Check for existing order by order_number if provided
      existing = find_existing_record(row)
      attributes = build_attributes(row, customer, total_amount)

      if existing
        if existing.update(attributes.except(:order_number))
          import_run.increment_progress!(updated: true)
        else
          add_error(row_number, "Update failed: #{existing.errors.full_messages.join(', ')}")
        end
      else
        order = business.orders.new(attributes)

        if order.save
          import_run.increment_progress!(created: true)
        else
          add_error(row_number, "Create failed: #{order.errors.full_messages.join(', ')}")
        end
      end
    end

    def find_existing_record(row)
      order_number = row['order_number']&.strip
      return nil if order_number.blank?

      business.orders.find_by(order_number: order_number)
    end

    def build_attributes(row, customer, total_amount)
      attrs = {
        tenant_customer: customer,
        total_amount: total_amount,
        status: :pending_payment,
        order_type: :product
      }

      # Optional fields
      if row['order_number'].present?
        attrs[:order_number] = row['order_number'].strip
      end

      if row['tax_amount'].present?
        tax_amount = parse_decimal(row['tax_amount'])
        attrs[:tax_amount] = tax_amount if tax_amount
      end

      if row['shipping_amount'].present?
        shipping_amount = parse_decimal(row['shipping_amount'])
        attrs[:shipping_amount] = shipping_amount if shipping_amount
      end

      if row['shipping_address'].present?
        attrs[:shipping_address] = row['shipping_address'].strip
      end

      if row['billing_address'].present?
        attrs[:billing_address] = row['billing_address'].strip
      end

      if row['notes'].present?
        attrs[:notes] = row['notes'].strip
      end

      if row['order_type'].present?
        order_type = row['order_type'].to_s.strip.downcase
        attrs[:order_type] = order_type if Order.order_types.key?(order_type)
      end

      if row['status'].present?
        status = row['status'].to_s.strip.downcase
        # Order uses string status, not enum
        valid_statuses = %w[pending_payment paid cancelled shipped refunded processing completed]
        attrs[:status] = status if valid_statuses.include?(status)
      end

      attrs
    end
  end
end
