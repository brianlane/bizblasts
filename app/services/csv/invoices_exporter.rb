# frozen_string_literal: true

module Csv
  class InvoicesExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Invoice Number', 'Customer Email', 'Customer Name',
        'Status', 'Amount', 'Tax Amount', 'Total Amount',
        'Due Date', 'Balance Due', 'Created At'
      ]
    end

    def row_for(invoice)
      [
        invoice.id,
        invoice.invoice_number,
        invoice.tenant_customer&.email,
        invoice.tenant_customer&.full_name,
        invoice.status,
        format_currency(invoice.amount),
        format_currency(invoice.tax_amount),
        format_currency(invoice.total_amount),
        format_date(invoice.due_date),
        format_currency(invoice.balance_due),
        format_datetime(invoice.created_at)
      ]
    end

    def sample_row
      [
        '', 'INV-000001', 'customer@example.com', 'John Doe',
        'pending', '100.00', '8.00', '108.00',
        '2025-02-01', '108.00', ''
      ]
    end

    def default_records
      business.invoices
              .includes(:tenant_customer)
              .order(created_at: :desc)
    end

    def export_name
      'invoices'
    end
  end
end
