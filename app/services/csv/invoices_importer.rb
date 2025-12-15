# frozen_string_literal: true

module Csv
  class InvoicesImporter < BaseImporter
    protected

    def required_headers
      %w[customer_email amount due_date]
    end

    def process_row(row, row_number)
      customer_email = row['customer_email']&.strip&.downcase
      amount = parse_decimal(row['amount'])
      due_date = parse_date(row['due_date'])

      if customer_email.blank?
        add_error(row_number, 'Customer email is required')
        return
      end

      if amount.nil? || amount < 0
        add_error(row_number, "Invalid amount: #{row['amount']}")
        return
      end

      if due_date.nil?
        add_error(row_number, "Invalid due date: #{row['due_date']}")
        return
      end

      # Find customer
      customer = business.tenant_customers.find_by('LOWER(email) = ?', customer_email)
      unless customer
        add_error(row_number, "Customer not found: #{customer_email}")
        return
      end

      # Check for existing invoice by invoice_number if provided
      existing = find_existing_record(row)
      attributes = build_attributes(row, customer, amount, due_date)

      if existing
        if existing.update(attributes.except(:invoice_number))
          import_run.increment_progress!(updated: true)
        else
          add_error(row_number, "Update failed: #{existing.errors.full_messages.join(', ')}")
        end
      else
        invoice = business.invoices.new(attributes)

        if invoice.save
          import_run.increment_progress!(created: true)
        else
          add_error(row_number, "Create failed: #{invoice.errors.full_messages.join(', ')}")
        end
      end
    end

    def find_existing_record(row)
      invoice_number = row['invoice_number']&.strip
      return nil if invoice_number.blank?

      business.invoices.find_by(invoice_number: invoice_number)
    end

    def build_attributes(row, customer, amount, due_date)
      attrs = {
        tenant_customer: customer,
        amount: amount,
        due_date: due_date,
        status: :pending
      }

      # Optional fields
      if row['invoice_number'].present?
        attrs[:invoice_number] = row['invoice_number'].strip
      end

      if row['tax_amount'].present?
        tax_amount = parse_decimal(row['tax_amount'])
        attrs[:tax_amount] = tax_amount if tax_amount
      end

      if row['total_amount'].present?
        total_amount = parse_decimal(row['total_amount'])
        attrs[:total_amount] = total_amount if total_amount
      else
        attrs[:total_amount] = amount + (attrs[:tax_amount] || 0)
      end

      if row['status'].present?
        status = row['status'].to_s.strip.downcase
        attrs[:status] = status if Invoice.statuses.key?(status)
      end

      attrs
    end
  end
end
