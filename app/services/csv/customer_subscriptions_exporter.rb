# frozen_string_literal: true

module Csv
  class CustomerSubscriptionsExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Customer Email', 'Customer Name', 'Subscription Type',
        'Item Name', 'Price', 'Frequency', 'Status',
        'Next Billing Date', 'Created At'
      ]
    end

    def row_for(subscription)
      item_name = subscription.product&.name || subscription.service&.name
      [
        subscription.id,
        subscription.tenant_customer&.email,
        subscription.tenant_customer&.full_name,
        subscription.subscription_type,
        item_name,
        format_currency(subscription.subscription_price),
        subscription.frequency,
        subscription.status,
        format_date(subscription.next_billing_date),
        format_datetime(subscription.created_at)
      ]
    end

    def sample_row
      [
        '', 'customer@example.com', 'John Doe', 'product_subscription',
        'Monthly Box', '29.99', 'monthly', 'active',
        '2025-02-01', ''
      ]
    end

    def default_records
      business.customer_subscriptions
              .includes(:tenant_customer, :product, :service)
              .order(created_at: :desc)
    end

    def export_name
      'customer_subscriptions'
    end
  end
end
