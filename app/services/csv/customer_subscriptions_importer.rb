# frozen_string_literal: true

module Csv
  class CustomerSubscriptionsImporter < BaseImporter
    protected

    def required_headers
      %w[customer_email item_name frequency]
    end

    def process_row(row, row_number)
      customer_email = row['customer_email']&.strip&.downcase
      item_name = row['item_name']&.strip
      frequency = row['frequency']&.strip&.downcase

      if customer_email.blank?
        add_error(row_number, 'Customer email is required')
        return
      end

      if item_name.blank?
        add_error(row_number, 'Item name is required')
        return
      end

      unless CustomerSubscription.frequencies.key?(frequency)
        add_error(row_number, "Invalid frequency: #{row['frequency']}. Valid options: #{CustomerSubscription.frequencies.keys.join(', ')}")
        return
      end

      # Find customer
      customer = business.tenant_customers.find_by('LOWER(email) = ?', customer_email)
      unless customer
        add_error(row_number, "Customer not found: #{customer_email}")
        return
      end

      # Find product or service
      product = business.products.find_by('LOWER(name) = ?', item_name.downcase)
      service = business.services.find_by('LOWER(name) = ?', item_name.downcase) unless product

      unless product || service
        add_error(row_number, "Product or service not found: #{item_name}")
        return
      end

      # Subscriptions are create-only
      attributes = build_attributes(row, customer, product, service, frequency)
      subscription = business.customer_subscriptions.new(attributes)

      if subscription.save
        import_run.increment_progress!(created: true)
      else
        add_error(row_number, "Create failed: #{subscription.errors.full_messages.join(', ')}")
      end
    end

    def build_attributes(row, customer, product, service, frequency)
      item = product || service
      price = parse_decimal(row['price']) || item.price

      attrs = {
        tenant_customer: customer,
        frequency: frequency,
        subscription_price: price,
        next_billing_date: Date.current + 1.month,
        billing_day_of_month: Date.current.day,
        status: :active
      }

      if product
        attrs[:product] = product
        attrs[:subscription_type] = 'product_subscription'
      else
        attrs[:service] = service
        attrs[:subscription_type] = 'service_subscription'
      end

      # Optional fields
      if row['next_billing_date'].present?
        next_billing_date = parse_date(row['next_billing_date'])
        if next_billing_date
          attrs[:next_billing_date] = next_billing_date
          attrs[:billing_day_of_month] = next_billing_date.day
        end
      end

      if row['status'].present?
        status = row['status'].to_s.strip.downcase
        attrs[:status] = status if CustomerSubscription.statuses.key?(status)
      end

      if row['notes'].present?
        attrs[:notes] = row['notes'].strip
      end

      attrs
    end
  end
end
