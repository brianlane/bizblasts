# frozen_string_literal: true

module Csv
  class PaymentsExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Invoice Number', 'Customer Email', 'Customer Name',
        'Amount', 'Payment Method', 'Status', 'Paid At',
        'Tip Amount', 'Stripe Payment ID', 'Created At'
      ]
    end

    def row_for(payment)
      [
        payment.id,
        payment.invoice&.invoice_number,
        payment.tenant_customer&.email,
        payment.tenant_customer&.full_name,
        format_currency(payment.amount),
        payment.payment_method,
        payment.status,
        format_datetime(payment.paid_at),
        format_currency(payment.tip_amount),
        payment.stripe_payment_intent_id,
        format_datetime(payment.created_at)
      ]
    end

    def sample_row
      [
        '', 'INV-000001', 'customer@example.com', 'John Doe',
        '108.00', 'credit_card', 'completed', '2025-01-15T14:30:00Z',
        '10.00', '', ''
      ]
    end

    def default_records
      business.payments
              .includes(:tenant_customer, :invoice)
              .order(created_at: :desc)
    end

    def export_name
      'payments'
    end
  end
end
