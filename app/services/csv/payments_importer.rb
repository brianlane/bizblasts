# frozen_string_literal: true

module Csv
  class PaymentsImporter < BaseImporter
    protected

    def required_headers
      %w[invoice_number amount payment_method]
    end

    def process_row(row, row_number)
      invoice_number = row['invoice_number']&.strip
      amount = parse_decimal(row['amount'])
      payment_method = row['payment_method']&.strip&.downcase

      if invoice_number.blank?
        add_error(row_number, 'Invoice number is required')
        return
      end

      if amount.nil? || amount <= 0
        add_error(row_number, "Invalid amount: #{row['amount']}")
        return
      end

      unless Payment.payment_methods.key?(payment_method)
        add_error(row_number, "Invalid payment method: #{row['payment_method']}. Valid options: #{Payment.payment_methods.keys.join(', ')}")
        return
      end

      # Find invoice
      invoice = business.invoices.find_by(invoice_number: invoice_number)
      unless invoice
        add_error(row_number, "Invoice not found: #{invoice_number}")
        return
      end

      # Payments are create-only (no update matching for financial integrity)
      attributes = build_attributes(row, invoice, amount, payment_method)
      payment = business.payments.new(attributes)

      if payment.save
        import_run.increment_progress!(created: true)
      else
        add_error(row_number, "Create failed: #{payment.errors.full_messages.join(', ')}")
      end
    end

    def build_attributes(row, invoice, amount, payment_method)
      attrs = {
        invoice: invoice,
        tenant_customer: invoice.tenant_customer,
        amount: amount,
        payment_method: payment_method,
        status: :completed
      }

      # Optional fields
      if row['paid_at'].present?
        paid_at = parse_datetime(row['paid_at'])
        attrs[:paid_at] = paid_at if paid_at
      else
        attrs[:paid_at] = Time.current
      end

      if row['tip_amount'].present?
        tip_amount = parse_decimal(row['tip_amount'])
        attrs[:tip_amount] = tip_amount if tip_amount && tip_amount >= 0
      end

      if row['status'].present?
        status = row['status'].to_s.strip.downcase
        attrs[:status] = status if Payment.statuses.key?(status)
      end

      attrs
    end
  end
end
