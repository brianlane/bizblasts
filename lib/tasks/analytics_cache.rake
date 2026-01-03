# frozen_string_literal: true

namespace :analytics do
  desc "Populate cached analytics fields for all tenant customers"
  task populate_cache: :environment do
    puts "Starting to populate cached analytics fields..."

    total_customers = TenantCustomer.count
    processed = 0
    batch_size = 100

    TenantCustomer.find_each(batch_size: batch_size) do |customer|
      customer.update_cached_analytics_fields!
      processed += 1

      if processed % batch_size == 0
        puts "Processed #{processed}/#{total_customers} customers..."
        GC.start
      end
    end

    puts "Completed! Populated cached analytics for #{processed} customers."
  end

  desc "Refresh cached analytics fields for customers with recent activity"
  task refresh_recent: :environment do
    puts "Refreshing cached analytics for customers with activity in the last 30 days..."

    # Find customers with recent payments
    recent_customer_ids = Payment.where(created_at: 30.days.ago..Time.current)
                                 .joins(invoice: :invoiceable)
                                 .where(invoiceable_type: ['Booking', 'Order'])
                                 .select('DISTINCT CASE
                                           WHEN invoiceables.invoiceable_type = \'Booking\' THEN bookings.tenant_customer_id
                                           WHEN invoiceables.invoiceable_type = \'Order\' THEN orders.tenant_customer_id
                                         END as customer_id')
                                 .pluck(:customer_id)
                                 .compact
                                 .uniq

    puts "Found #{recent_customer_ids.count} customers with recent activity"

    TenantCustomer.where(id: recent_customer_ids).find_each do |customer|
      customer.update_cached_analytics_fields!
    end

    puts "Completed refresh for #{recent_customer_ids.count} customers."
  end
end
