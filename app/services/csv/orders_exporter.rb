# frozen_string_literal: true

module Csv
  class OrdersExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Order Number', 'Customer Email', 'Customer Name',
        'Order Type', 'Status', 'Subtotal', 'Tax Amount',
        'Shipping Amount', 'Total Amount', 'Created At'
      ]
    end

    def row_for(order)
      [
        order.id,
        order.order_number,
        order.tenant_customer&.email,
        order.tenant_customer&.full_name,
        order.order_type,
        order.status,
        format_currency(order.subtotal_amount),
        format_currency(order.tax_amount),
        format_currency(order.shipping_amount),
        format_currency(order.total_amount),
        format_datetime(order.created_at)
      ]
    end

    def sample_row
      [
        '', 'ORD-000001', 'customer@example.com', 'John Doe',
        'product', 'paid', '50.00', '4.00',
        '5.00', '59.00', ''
      ]
    end

    def default_records
      business.orders
              .includes(:tenant_customer)
              .order(created_at: :desc)
    end

    def export_name
      'orders'
    end
  end
end
