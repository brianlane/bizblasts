# frozen_string_literal: true

module Analytics
  # Job for generating daily analytics snapshots
  # Runs daily at 2 AM to generate previous day's summary
  class DailySnapshotJob < ApplicationJob
    queue_as :analytics

    # Domain patterns for traffic source categorization
    SEARCH_ENGINE_DOMAINS = %w[google bing yahoo duckduckgo].freeze
    SOCIAL_NETWORK_DOMAINS = %w[facebook twitter instagram linkedin pinterest tiktok].freeze

    # Configuration thresholds (from config/initializers/analytics.rb)
    def self.slow_threshold
      Rails.application.config.analytics.snapshot_slow_threshold
    end

    def self.max_duration
      Rails.application.config.analytics.snapshot_max_duration
    end

    def self.error_threshold
      Rails.application.config.analytics.snapshot_error_threshold
    end

    def perform(date = nil)
      date ||= Date.yesterday
      Rails.logger.info "[DailySnapshot] Generating snapshots for #{date}..."

      start_time = Time.current
      business_count = 0
      error_count = 0
      slow_business_ids = []

      # Generate snapshot for each active business
      # OPTIMIZED: Reduced batch size and added memory cleanup
      Business.active.find_each(batch_size: 10) do |business|
        business_start = Time.current

        generate_snapshot(business, date)
        business_count += 1

        # Track slow business processing
        business_elapsed = Time.current - business_start
        if business_elapsed > self.class.slow_threshold
          slow_business_ids << business.id
          Rails.logger.warn "[DailySnapshot] Slow processing for business #{business.id}: #{business_elapsed.round(2)}s"
        end

        # OPTIMIZATION: Clear ActiveRecord query cache and trigger GC periodically
        if business_count % 10 == 0
          ActiveRecord::Base.connection.clear_query_cache
          GC.start

          # Log memory usage
          memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
          Rails.logger.info "[DailySnapshot] Progress: #{business_count} businesses processed, Memory: #{memory_mb}MB"
        end
      rescue StandardError => e
        error_count += 1
        Rails.logger.error "[DailySnapshot] Error generating snapshot for business #{business.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        # Alert if too many errors
        if error_count > self.class.error_threshold
          Rails.logger.error "[DailySnapshot] Too many errors (#{error_count}), continuing but alerting"
        end
      end

      elapsed = Time.current - start_time
      avg_time = business_count > 0 ? (elapsed / business_count).round(3) : 0

      Rails.logger.info "[DailySnapshot] Complete - #{business_count} businesses, #{error_count} errors, #{elapsed.round(2)}s total (avg: #{avg_time}s/business)"

      if slow_business_ids.any?
        Rails.logger.warn "[DailySnapshot] Slow businesses: #{slow_business_ids.join(', ')}"
      end

      # Alert if job took too long
      if elapsed > self.class.max_duration
        Rails.logger.error "[DailySnapshot] Job duration exceeded threshold: #{elapsed.round(2)}s (max: #{self.class.max_duration}s)"
      end
    end

    private

    def generate_snapshot(business, date)
      # Set tenant context
      ActsAsTenant.with_tenant(business) do
        # Skip if snapshot already exists
        existing = business.analytics_snapshots.find_by(
          snapshot_type: 'daily',
          period_start: date,
          period_end: date
        )

        if existing
          Rails.logger.debug "[DailySnapshot] Snapshot already exists for business #{business.id} on #{date}"
          return
        end

        # Calculate metrics for the date
        metrics = calculate_metrics(business, date)

        # Create snapshot in a transaction for atomicity
        ActiveRecord::Base.transaction do
          business.analytics_snapshots.create!(
            snapshot_type: 'daily',
            period_start: date,
            period_end: date,
            generated_at: Time.current,
            **metrics
          )
        end

        Rails.logger.info "[DailySnapshot] Created snapshot for business #{business.id} on #{date}"
      end
      # OPTIMIZATION: Ensure memory cleanup after each business
      GC.start
    end

    def calculate_metrics(business, date)
      date_range = date.beginning_of_day..date.end_of_day
      
      sessions = business.visitor_sessions.where(session_start: date_range)
      page_views = business.page_views.where(created_at: date_range)
      clicks = business.click_events.where(created_at: date_range)
      
      total_sessions = sessions.count
      
      {
        unique_visitors: sessions.distinct.count(:visitor_fingerprint),
        total_page_views: page_views.count,
        total_sessions: total_sessions,
        bounce_rate: calculate_bounce_rate(sessions, total_sessions),
        avg_session_duration: sessions.where.not(duration_seconds: nil).average(:duration_seconds)&.round(0) || 0,
        pages_per_session: total_sessions > 0 ? (page_views.count.to_f / total_sessions).round(2) : 0,
        total_clicks: clicks.count,
        unique_pages_viewed: page_views.distinct.count(:page_path),
        total_conversions: sessions.converted.count,
        conversion_rate: calculate_conversion_rate(sessions, total_sessions),
        total_conversion_value: sessions.converted.sum(:conversion_value).to_f,
        booking_metrics: calculate_booking_metrics(business, date_range),
        product_metrics: calculate_product_metrics(business, date_range),
        service_metrics: calculate_service_metrics(business, date_range),
        estimate_metrics: calculate_estimate_metrics(business, date_range),
        revenue_metrics: calculate_revenue_metrics(business, date_range),
        traffic_sources: calculate_traffic_sources(sessions),
        top_referrers: calculate_top_referrers(sessions),
        top_pages: calculate_top_pages(page_views),
        device_breakdown: calculate_device_breakdown(sessions),
        geo_breakdown: calculate_geo_breakdown(sessions),
        campaign_metrics: calculate_campaign_metrics(sessions),
        customer_metrics: calculate_customer_metrics(business, date_range),
        staff_metrics: calculate_staff_metrics(business, date_range),
        operational_metrics: calculate_operational_metrics(business, date_range),
        inventory_metrics: calculate_inventory_metrics(business, date_range)
      }
    end

    def calculate_bounce_rate(sessions, total)
      return 0.0 if total.zero?
      (sessions.bounced.count.to_f / total * 100).round(2)
    end

    def calculate_conversion_rate(sessions, total)
      return 0.0 if total.zero?
      (sessions.converted.count.to_f / total * 100).round(2)
    end

    def calculate_booking_metrics(business, date_range)
      bookings = business.bookings.where(created_at: date_range)
      
      {
        total: bookings.count,
        completed: bookings.completed.count,
        cancelled: bookings.cancelled.count,
        revenue: bookings.completed.joins(:service).sum('services.price').to_f,
        avg_value: bookings.completed.joins(:service).any? ?
          (bookings.completed.joins(:service).sum('services.price').to_f / bookings.completed.joins(:service).count).round(2) : 0
      }
    end

    def calculate_product_metrics(business, date_range)
      orders = business.orders.where(created_at: date_range)
      product_clicks = business.click_events.where(created_at: date_range, category: 'product')
      
      {
        views: product_clicks.count,
        purchases: orders.where(status: [:completed, :delivered]).count,
        revenue: orders.where(status: [:completed, :delivered]).sum(:total_amount).to_f,
        conversion_rate: product_clicks.count > 0 ?
          (orders.count.to_f / product_clicks.distinct.count(:session_id) * 100).round(2) : 0
      }
    end

    def calculate_service_metrics(business, date_range)
      service_clicks = business.click_events.where(created_at: date_range, category: 'service')
      bookings = business.bookings.where(created_at: date_range)
      
      {
        views: service_clicks.count,
        bookings: bookings.count,
        conversion_rate: service_clicks.count > 0 ?
          (bookings.count.to_f / service_clicks.distinct.count(:session_id) * 100).round(2) : 0
      }
    end

    def calculate_estimate_metrics(business, date_range)
      estimates = business.estimates.where(created_at: date_range)
      
      sent = estimates.sent.count
      viewed = estimates.viewed.count
      approved = estimates.approved.count
      total_value = estimates.sum(:total).to_f
      
      {
        sent: sent,
        viewed: viewed,
        approved: approved,
        total_value: total_value,
        conversion_rate: sent > 0 ? (approved.to_f / sent * 100).round(2) : 0
      }
    end

    def calculate_traffic_sources(sessions)
      # Use SQL-based categorization for performance (avoids loading all sessions into memory)
      timed_query("traffic_sources") do
        total = sessions.count
        return { direct: 0, organic: 0, social: 0, referral: 0, paid: 0 } if total.zero?

        # Paid traffic - has paid UTM medium
        paid = sessions.where("LOWER(utm_medium) IN ('cpc', 'ppc', 'paid')").count

        # Direct traffic - no referrer AND not paid (exclude paid sessions without referrer)
        direct = sessions.where(first_referrer_domain: [nil, ''])
                         .where("utm_medium IS NULL OR LOWER(utm_medium) NOT IN ('cpc', 'ppc', 'paid')").count

        # Organic traffic - from search engines (using parameterized LIKE patterns)
        organic = sessions.where(
          build_domain_like_conditions(SEARCH_ENGINE_DOMAINS)
        ).where("utm_medium IS NULL OR LOWER(utm_medium) NOT IN ('cpc', 'ppc', 'paid')").count

        # Social traffic - from social networks (using parameterized LIKE patterns)
        social = sessions.where(
          build_domain_like_conditions(SOCIAL_NETWORK_DOMAINS)
        ).where("utm_medium IS NULL OR LOWER(utm_medium) NOT IN ('cpc', 'ppc', 'paid')").count

        # Referral - everything else with a referrer
        referral = total - paid - direct - organic - social

        {
          direct: (direct.to_f / total * 100).round(1),
          organic: (organic.to_f / total * 100).round(1),
          social: (social.to_f / total * 100).round(1),
          referral: ([referral, 0].max.to_f / total * 100).round(1),
          paid: (paid.to_f / total * 100).round(1)
        }
      end
    end

    # Build parameterized LIKE conditions for domain matching
    # Returns an array suitable for ActiveRecord where clause: ["sql", *bindings]
    def build_domain_like_conditions(domains)
      conditions = domains.map { "LOWER(first_referrer_domain) LIKE ?" }.join(' OR ')
      bindings = domains.map { |d| "%#{d}%" }
      [conditions, *bindings]
    end

    def calculate_top_referrers(sessions, limit: 10)
      sessions
        .where.not(first_referrer_domain: [nil, ''])
        .group(:first_referrer_domain)
        .order('count_all DESC')
        .limit(limit)
        .count
        .map { |domain, count| { domain: domain, visits: count } }
    end

    def calculate_top_pages(page_views, limit: 10)
      page_views
        .group(:page_path)
        .select('page_path, COUNT(*) as views, AVG(time_on_page) as avg_time')
        .order('views DESC')
        .limit(limit)
        .map do |pv|
          {
            path: pv.page_path,
            views: pv.views,
            avg_time: pv.avg_time&.round(0) || 0
          }
        end
    end

    def calculate_device_breakdown(sessions)
      total = sessions.count
      return { desktop: 0, mobile: 0, tablet: 0 } if total.zero?
      
      breakdown = sessions.group(:device_type).count
      
      {
        desktop: ((breakdown['desktop'] || 0).to_f / total * 100).round(1),
        mobile: ((breakdown['mobile'] || 0).to_f / total * 100).round(1),
        tablet: ((breakdown['tablet'] || 0).to_f / total * 100).round(1)
      }
    end

    def calculate_geo_breakdown(sessions)
      sessions
        .where.not(country: nil)
        .group(:country)
        .order('count_all DESC')
        .limit(10)
        .count
    end

    def calculate_campaign_metrics(sessions)
      sessions
        .where.not(utm_campaign: nil)
        .group(:utm_campaign)
        .select('utm_campaign, COUNT(*) as visits, SUM(CASE WHEN converted THEN 1 ELSE 0 END) as conversions, SUM(conversion_value) as revenue')
        .each_with_object({}) do |session, hash|
          hash[session.utm_campaign] = {
            visits: session.visits,
            conversions: session.conversions,
            revenue: session.revenue.to_f
          }
        end
    end

    def calculate_customer_metrics(business, date_range)
      # Use lifecycle service to calculate customer metrics
      lifecycle_service = Analytics::CustomerLifecycleService.new(business)
      churn_service = Analytics::ChurnPredictionService.new(business)

      # Get customers active in this period (with completed purchases only to match new_customers criteria)
      completed_status = Payment.statuses[:completed]
      customers_in_period = business.tenant_customers
                                   .joins("LEFT JOIN bookings ON bookings.tenant_customer_id = tenant_customers.id
                                          LEFT JOIN invoices AS booking_invoices ON booking_invoices.booking_id = bookings.id
                                          LEFT JOIN payments AS booking_payments ON booking_payments.invoice_id = booking_invoices.id")
                                   .joins("LEFT JOIN orders ON orders.tenant_customer_id = tenant_customers.id
                                          LEFT JOIN invoices AS order_invoices ON order_invoices.order_id = orders.id
                                          LEFT JOIN payments AS order_payments ON order_payments.invoice_id = order_invoices.id")
                                   .where("(bookings.created_at BETWEEN ? AND ? AND booking_payments.status = ?) OR
                                           (orders.created_at BETWEEN ? AND ? AND order_payments.status = ?)",
                                          date_range.begin, date_range.end, completed_status,
                                          date_range.begin, date_range.end, completed_status)
                                   .distinct

      # Calculate new customers using SQL aggregation (first purchase in this period)
      # Find earliest completed purchase date across ALL purchase types for each customer
      # CRITICAL: Must filter by business_id since raw SQL bypasses ActsAsTenant scoping
      new_customers = customers_in_period.select('tenant_customers.id').where(
        "tenant_customers.id IN (
          SELECT customer_id
          FROM (
            SELECT customer_id, MIN(purchase_date) AS first_purchase_date
            FROM (
              SELECT bookings.tenant_customer_id AS customer_id,
                     bookings.created_at AS purchase_date
              FROM bookings
              INNER JOIN invoices ON invoices.booking_id = bookings.id
              INNER JOIN payments ON payments.invoice_id = invoices.id
              WHERE payments.status = ?
                AND bookings.business_id = ?

              UNION ALL

              SELECT orders.tenant_customer_id AS customer_id,
                     orders.created_at AS purchase_date
              FROM orders
              INNER JOIN invoices ON invoices.order_id = orders.id
              INNER JOIN payments ON payments.invoice_id = invoices.id
              WHERE payments.status = ?
                AND orders.business_id = ?
            ) AS all_purchases
            GROUP BY customer_id
          ) AS first_purchases
          WHERE first_purchase_date BETWEEN ? AND ?
        )",
        completed_status, business.id, completed_status, business.id, date_range.begin, date_range.end
      ).count

      # Calculate repeat customers (had previous purchases)
      repeat_customers = customers_in_period.count - new_customers

      # Get segment distribution
      segment_summary = lifecycle_service.segment_summary

      # Get churn statistics
      churn_stats = churn_service.churn_statistics

      # Calculate total revenue using SQL aggregation instead of iterating
      total_revenue_from_customers = business.payments
                                            .where(status: :completed, created_at: date_range)
                                            .sum(:amount).to_f

      {
        active_customers: customers_in_period.count,
        new_customers: new_customers,
        repeat_customers: repeat_customers,
        avg_clv: lifecycle_service.customer_metrics_summary[:avg_clv] || 0,
        arpc: lifecycle_service.calculate_arpc(1.day, date_range: date_range), # ARPC for this day
        repeat_rate: lifecycle_service.customer_metrics_summary[:repeat_customer_rate] || 0,
        segment_distribution: segment_summary[:percentages] || {},
        churn_risk: {
          high: churn_stats[:high_risk] || 0,
          medium: churn_stats[:medium_risk] || 0,
          low: churn_stats[:low_risk] || 0
        },
        total_revenue_from_customers: total_revenue_from_customers.round(2)
      }
    rescue StandardError => e
      Rails.logger.error "[DailySnapshot] Error calculating customer metrics: #{e.message}"
      {
        active_customers: 0,
        new_customers: 0,
        repeat_customers: 0,
        avg_clv: 0,
        arpc: 0,
        repeat_rate: 0,
        segment_distribution: {},
        churn_risk: { high: 0, medium: 0, low: 0 },
        total_revenue_from_customers: 0
      }
    end

    def calculate_staff_metrics(business, date_range)
      staff_service = Analytics::StaffPerformanceService.new(business)
      period = 1.day # For daily snapshot, use 1 day period

      staff_members = business.staff_members

      # Find active staff using a single query
      active_staff_count = business.staff_members
                                  .joins(:bookings)
                                  .where(bookings: { created_at: date_range })
                                  .distinct
                                  .count

      total_bookings = business.bookings.where(created_at: date_range).count
      total_revenue = business.bookings
                              .where(created_at: date_range)
                              .joins(invoice: :payments)
                              .where(payments: { status: :completed })
                              .sum('payments.amount').to_f

      # Find top performer using a single query with GROUP BY
      top_performer_data = business.staff_members
                                  .joins(bookings: { invoice: :payments })
                                  .where(bookings: { created_at: date_range })
                                  .where(payments: { status: :completed })
                                  .group('staff_members.id')
                                  .select('staff_members.id, staff_members.name, SUM(payments.amount) as total_revenue')
                                  .order('total_revenue DESC')
                                  .first

      top_performer_name = if top_performer_data
                            top_performer_data.name
                          else
                            'N/A'
                          end

      {
        total_staff: staff_members.count,
        active_staff: active_staff_count,
        total_bookings: total_bookings,
        total_revenue: total_revenue,
        avg_bookings_per_staff: active_staff_count > 0 ? (total_bookings.to_f / active_staff_count).round(1) : 0,
        avg_revenue_per_staff: active_staff_count > 0 ? (total_revenue / active_staff_count).round(2) : 0,
        top_performer: top_performer_name
      }
    rescue StandardError => e
      Rails.logger.error "[DailySnapshot] Error calculating staff metrics: #{e.message}"
      {
        total_staff: 0,
        active_staff: 0,
        total_bookings: 0,
        total_revenue: 0,
        avg_bookings_per_staff: 0,
        avg_revenue_per_staff: 0,
        top_performer: 'N/A'
      }
    end

    def calculate_revenue_metrics(business, date_range)
      revenue_service = Analytics::RevenueForecastService.new(business)

      # Get revenue data for the period
      payments = business.payments.where(created_at: date_range, status: :completed)
      total_revenue = payments.sum(:amount).to_f

      # Get refund data
      # Filter by updated_at since refunds occur when status changes to :refunded (no refunded_at column exists)
      # This captures payments that were refunded during this date range, not when they were originally created
      refunds = business.payments.where(updated_at: date_range, status: :refunded)
      refund_amount = refunds.sum(:amount).to_f

      # Revenue by category
      booking_revenue = business.bookings
                               .where(created_at: date_range)
                               .joins(invoice: :payments)
                               .where(payments: { status: :completed })
                               .sum('payments.amount').to_f

      order_revenue = business.orders
                             .where(created_at: date_range)
                             .joins(invoice: :payments)
                             .where(payments: { status: :completed })
                             .sum('payments.amount').to_f

      subscription_revenue = business.subscription_transactions
                                    .where(created_at: date_range, status: :completed)
                                    .sum(:amount).to_f

      {
        total_revenue: total_revenue,
        booking_revenue: booking_revenue,
        order_revenue: order_revenue,
        subscription_revenue: subscription_revenue,
        refund_amount: refund_amount,
        refund_count: refunds.count,
        refund_rate: total_revenue > 0 ? ((refund_amount / total_revenue) * 100).round(2) : 0,
        daily_average: total_revenue,
        net_revenue: (total_revenue - refund_amount).round(2)
      }
    rescue StandardError => e
      Rails.logger.error "[DailySnapshot] Error calculating revenue metrics: #{e.message}"
      {
        total_revenue: 0,
        booking_revenue: 0,
        order_revenue: 0,
        subscription_revenue: 0,
        refund_amount: 0,
        refund_count: 0,
        refund_rate: 0,
        daily_average: 0,
        net_revenue: 0
      }
    end

    def calculate_operational_metrics(business, date_range)
      operations_service = Analytics::OperationalEfficiencyService.new(business)

      # Filter by start_time to capture operational events that occurred on this day
      # (no-shows, cancellations, completions happen on the appointment date, not creation date)
      bookings = business.bookings.where(start_time: date_range)
      total_bookings = bookings.count

      # No-show metrics
      no_shows = bookings.where(status: :no_show)
      no_show_count = no_shows.count
      no_show_rate = total_bookings > 0 ? ((no_show_count.to_f / total_bookings) * 100).round(2) : 0

      # Cancellation metrics
      cancelled = bookings.where(status: :cancelled)
      cancellation_count = cancelled.count
      cancellation_rate = total_bookings > 0 ? ((cancellation_count.to_f / total_bookings) * 100).round(2) : 0

      # Completion metrics
      completed = bookings.where(status: :completed)
      completion_count = completed.count
      completion_rate = total_bookings > 0 ? ((completion_count.to_f / total_bookings) * 100).round(2) : 0

      # Lead time calculation
      lead_times = bookings.map do |booking|
        next unless booking.start_time && booking.created_at
        ((booking.start_time - booking.created_at) / 1.day).to_i
      end.compact

      avg_lead_time = lead_times.any? ? (lead_times.sum / lead_times.count.to_f).round(1) : 0
      same_day_bookings = lead_times.count { |d| d == 0 }

      {
        total_bookings: total_bookings,
        completed_count: completion_count,
        completion_rate: completion_rate,
        no_show_count: no_show_count,
        no_show_rate: no_show_rate,
        cancellation_count: cancellation_count,
        cancellation_rate: cancellation_rate,
        avg_lead_time_days: avg_lead_time,
        same_day_bookings: same_day_bookings,
        estimated_lost_revenue: no_shows.joins(:service).sum('services.price').to_f
      }
    rescue StandardError => e
      Rails.logger.error "[DailySnapshot] Error calculating operational metrics: #{e.message}"
      {
        total_bookings: 0,
        completed_count: 0,
        completion_rate: 0,
        no_show_count: 0,
        no_show_rate: 0,
        cancellation_count: 0,
        cancellation_rate: 0,
        avg_lead_time_days: 0,
        same_day_bookings: 0,
        estimated_lost_revenue: 0
      }
    end

    def calculate_inventory_metrics(business, date_range)
      inventory_service = Analytics::InventoryIntelligenceService.new(business)

      # Get basic inventory counts
      products_with_stock = business.products.joins(:product_variants)
                                    .where.not(product_variants: { stock_quantity: nil })
                                    .distinct.count

      total_stock_quantity = business.product_variants.sum(:stock_quantity).to_i

      # Get stock valuation
      valuation = inventory_service.stock_valuation
      total_stock_value = valuation[:total_stock_value]

      # Get low stock alerts count
      low_stock_count = inventory_service.low_stock_alerts(7).count

      # Get stock movements for the day
      movements = business.stock_movements.where(created_at: date_range)
      stock_in = movements.inbound.sum(:quantity)
      stock_out = movements.outbound.sum(:quantity).abs
      adjustments = movements.where(movement_type: 'adjustment').count

      # Calculate units sold from orders
      # Filter by product_variant_id IS NOT NULL to identify product line items
      # (lineable_type stores the parent class 'Order', not the item type)
      # IMPORTANT: Filter by payment status to match revenue calculation (only count paid orders)
      #
      # NOTE: We use a subquery to avoid cartesian product when orders have multiple payments.
      # Joining orders -> line_items -> invoice -> payments would duplicate line items per payment,
      # causing inflated counts (e.g., 5 units with 2 payments would report 10 units sold).
      paid_order_ids = business.orders
                               .joins(invoice: :payments)
                               .where(created_at: date_range)
                               .where(payments: { status: :completed })
                               .select(:id)

      units_sold = LineItem.where(lineable_type: 'Order')
                           .where(lineable_id: paid_order_ids)
                           .where.not(product_variant_id: nil)
                           .sum(:quantity)

      # Get health score
      health_score = inventory_service.inventory_health_score[:score]

      {
        products_with_stock: products_with_stock,
        total_stock_quantity: total_stock_quantity,
        total_stock_value: total_stock_value,
        low_stock_count: low_stock_count,
        stock_in: stock_in,
        stock_out: stock_out,
        adjustments: adjustments,
        units_sold: units_sold,
        health_score: health_score
      }
    rescue StandardError => e
      Rails.logger.error "[DailySnapshot] Error calculating inventory metrics: #{e.message}"
      Rails.logger.error "[DailySnapshot] Backtrace: #{e.backtrace.first(5).join("\n")}"
      {
        products_with_stock: 0,
        total_stock_quantity: 0,
        total_stock_value: 0,
        low_stock_count: 0,
        stock_in: 0,
        stock_out: 0,
        adjustments: 0,
        units_sold: 0,
        health_score: 0
      }
    end

    # Helper method to time and log slow queries
    def timed_query(name)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      if elapsed > self.class.slow_threshold
        Rails.logger.warn "[DailySnapshot] Slow query detected: #{name} took #{elapsed.round(3)}s"
      end

      result
    end
  end
end

