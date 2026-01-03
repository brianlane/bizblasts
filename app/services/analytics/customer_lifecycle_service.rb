# frozen_string_literal: true

module Analytics
  # Service for calculating customer lifetime value and segmentation metrics
  class CustomerLifecycleService
    include Analytics::QueryMonitoring

    attr_reader :business

    # Set custom slow query threshold
    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Calculate Customer Lifetime Value for a customer
    # CLV = Current Revenue + Predicted Future Revenue
    # Future Revenue = (Average Order Value × Purchase Frequency Per Year) × Expected Remaining Years
    def calculate_clv(customer)
      if customer.purchase_frequency.zero?
        return {
          total_value: customer.total_revenue,
          predicted_future_value: 0,
          avg_order_value: 0,
          purchase_frequency: 0,
          estimated_lifespan_years: 0
        }
      end

      avg_order_value = customer.total_revenue / customer.purchase_frequency
      historical_lifespan_years = customer.lifespan_days / 365.0

      # Estimate expected remaining lifetime (industry standard: 3 years for active customers)
      # Reduce remaining lifetime for customers who've been around longer
      expected_remaining_years = [3.0 - historical_lifespan_years, 1.0].max

      # Calculate predicted future value based on historical purchase patterns
      predicted_future_value = (avg_order_value * customer.purchase_frequency_per_year * expected_remaining_years).round(2)

      {
        total_value: customer.total_revenue,
        predicted_future_value: predicted_future_value,
        avg_order_value: avg_order_value.round(2),
        purchase_frequency: customer.purchase_frequency,
        estimated_lifespan_years: (historical_lifespan_years + expected_remaining_years).round(1)
      }
    end

    # Calculate Average Revenue Per Customer for a period
    # @param period [ActiveSupport::Duration] Time period (e.g., 30.days)
    # @param date_range [Range] Optional specific date range to use instead of period.ago..Time.current
    def calculate_arpc(period = 30.days, date_range: nil)
      # Use provided date_range or calculate from period
      range = date_range || (period.ago..Time.current)

      customers_with_activity = business.tenant_customers
                                        .joins("LEFT JOIN bookings ON bookings.tenant_customer_id = tenant_customers.id")
                                        .joins("LEFT JOIN orders ON orders.tenant_customer_id = tenant_customers.id")
                                        .where("bookings.created_at BETWEEN ? AND ? OR orders.created_at BETWEEN ? AND ?",
                                               range.begin, range.end, range.begin, range.end)
                                        .distinct

      customer_count = customers_with_activity.count
      return 0 if customer_count.zero?

      total_revenue = calculate_total_revenue(period, date_range: range)
      (total_revenue / customer_count).round(2)
    end

    # RFM (Recency, Frequency, Monetary) Segmentation
    # OPTIMIZED: Uses SQL aggregation instead of loading all customers into memory
    def customer_segments_rfm
      # Calculate quartiles using SQL
      quartiles = calculate_revenue_quartiles_sql

      # Use SQL CASE statements to calculate RFM scores in database
      customers_with_scores = business.tenant_customers
        .where('cached_purchase_frequency > 0')
        .select(
          :id,
          "CONCAT(first_name, ' ', last_name) as customer_name",
          :email,
          :cached_total_revenue,
          :cached_days_since_last_purchase,
          :cached_purchase_frequency,
          calculate_recency_score_sql,
          calculate_frequency_score_sql,
          calculate_monetary_score_sql(quartiles)
        )

      # Convert to hash array and assign segments
      customers_with_scores.map do |customer|
        {
          customer_id: customer.id,
          customer_name: customer.customer_name,
          email: customer.email,
          total_revenue: customer.total_revenue.to_f,
          recency_score: customer.recency_score,
          frequency_score: customer.frequency_score,
          monetary_score: customer.monetary_score,
          segment: determine_segment(customer.recency_score, customer.frequency_score, customer.monetary_score)
        }
      end
    end

    # Get customers by segment
    def customers_by_segment(segment_name)
      all_segments = customer_segments_rfm
      all_segments.select { |c| c[:segment] == segment_name }
    end

    # Get summary of all segments
    def segment_summary
      segments = customer_segments_rfm

      segment_counts = segments.group_by { |c| c[:segment] }
                               .transform_values(&:count)

      segment_values = segments.group_by { |c| c[:segment] }
                               .transform_values { |customers|
                                 customers.sum { |c| c[:total_revenue] }
                               }

      {
        counts: segment_counts,
        total_values: segment_values,
        percentages: segment_counts.transform_values { |count|
          ((count.to_f / segments.count) * 100).round(1)
        }
      }
    end

    # Calculate metrics for all customers
    # OPTIMIZED: Uses SQL aggregation instead of loading all customers
    def customer_metrics_summary(period = 30.days)
      # Use SQL COUNT to get totals without loading objects
      total_customers = business.tenant_customers.count
      active_customers = business.tenant_customers.where('cached_purchase_frequency > 0').count

      return empty_metrics_summary if active_customers.zero?

      # Use SQL aggregations for all metrics
      {
        total_customers: total_customers,
        active_customers: active_customers,
        avg_clv: business.tenant_customers.where('cached_purchase_frequency > 0').average(:cached_total_revenue)&.to_f&.round(2) || 0,
        arpc: calculate_arpc(period),
        repeat_customer_rate: calculate_repeat_rate_sql,
        avg_purchase_frequency: business.tenant_customers.where('cached_purchase_frequency > 0').average(:cached_purchase_frequency)&.to_f&.round(1) || 0,
        avg_days_between_purchases: business.tenant_customers.where('cached_avg_days_between_purchases IS NOT NULL').average(:cached_avg_days_between_purchases)&.to_f&.round(0) || 0
      }
    end

    private

    def calculate_total_revenue(period, date_range: nil)
      # Use provided date_range or calculate from period
      range = date_range || (period.ago..Time.current)

      booking_revenue = business.bookings
                               .where(created_at: range)
                               .joins(invoice: :payments)
                               .where(payments: { status: :completed })
                               .sum('payments.amount')

      order_revenue = business.orders
                             .where(created_at: range)
                             .joins(invoice: :payments)
                             .where(payments: { status: :completed })
                             .sum('payments.amount')

      booking_revenue + order_revenue
    end

    def calculate_recency_score(customer)
      days_since_purchase = customer.days_since_last_purchase || Float::INFINITY

      case days_since_purchase
      when 0..30 then 5
      when 31..60 then 4
      when 61..90 then 3
      when 91..180 then 2
      else 1
      end
    end

    def calculate_frequency_score(customer)
      frequency = customer.purchase_frequency

      case frequency
      when 10..Float::INFINITY then 5
      when 6..9 then 4
      when 3..5 then 3
      when 2 then 2
      else 1
      end
    end

    def calculate_monetary_score(customer, quartiles = nil)
      revenue = customer.total_revenue

      # Use business-specific quartiles for more accurate scoring
      # Accept pre-calculated quartiles to avoid O(n²) complexity when called in loops
      quartiles ||= calculate_revenue_quartiles

      case revenue
      when quartiles[:q4]..Float::INFINITY then 5
      when quartiles[:q3]...quartiles[:q4] then 4
      when quartiles[:q2]...quartiles[:q3] then 3
      when quartiles[:q1]...quartiles[:q2] then 2
      else 1
      end
    end

    # OPTIMIZED: Use SQL PERCENTILE_CONT instead of loading all revenues
    def calculate_revenue_quartiles_sql
      # Use PostgreSQL PERCENTILE_CONT for accurate quartile calculation
      result = business.tenant_customers
        .select(
          "PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cached_total_revenue) as q1",
          "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY cached_total_revenue) as q2",
          "PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY cached_total_revenue) as q3",
          "PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY cached_total_revenue) as q4"
        )
        .first

      return { q1: 0, q2: 0, q3: 0, q4: 0 } unless result

      {
        q1: result.q1&.to_f || 0,
        q2: result.q2&.to_f || 0,
        q3: result.q3&.to_f || 0,
        q4: result.q4&.to_f || 0
      }
    end

    # Legacy method for backward compatibility (calls SQL version)
    def calculate_revenue_quartiles
      calculate_revenue_quartiles_sql
    end

    def determine_segment(recency, frequency, monetary)
      total_score = recency + frequency + monetary

      # Champions: High on all dimensions
      return 'champions' if recency >= 4 && frequency >= 4 && monetary >= 4

      # Loyal Customers: High frequency, moderate value
      return 'loyal' if frequency >= 4 && monetary >= 3

      # Big Spenders: High monetary, lower frequency
      return 'big_spenders' if monetary >= 4 && frequency < 4

      # At Risk: Were valuable but declining recency
      return 'at_risk' if monetary >= 3 && recency <= 2

      # Lost: Haven't purchased in a long time
      return 'lost' if recency == 1

      # New Customers: Recent but low frequency
      return 'new' if recency >= 4 && frequency == 1

      # Occasional: Moderate on all dimensions
      return 'occasional' if total_score >= 6 && total_score <= 9

      # Hibernating: Low recency and frequency
      'hibernating'
    end

    # OPTIMIZED: Use SQL COUNT instead of loading all customers
    def calculate_repeat_rate_sql
      total_with_purchases = business.tenant_customers.where('cached_purchase_frequency > 0').count
      return 0 if total_with_purchases.zero?

      repeat_customers = business.tenant_customers.where('cached_purchase_frequency > 1').count
      ((repeat_customers.to_f / total_with_purchases) * 100).round(2)
    end

    # Legacy method for backward compatibility (renamed for clarity)
    def calculate_repeat_rate(customers)
      # If called with customers array, use old logic for compatibility
      customers_with_purchases = customers.select { |c| c.purchase_frequency > 0 }
      return 0 if customers_with_purchases.empty?

      repeat_customers = customers_with_purchases.count { |c| c.purchase_frequency > 1 }
      ((repeat_customers.to_f / customers_with_purchases.count) * 100).round(2)
    end

    def calculate_avg_days_between_purchases(customers)
      intervals = customers.map(&:avg_days_between_purchases).compact
      return 0 if intervals.empty?

      (intervals.sum.to_f / intervals.count).round(0)
    end

    # SQL helper methods for RFM score calculation
    def calculate_recency_score_sql
      <<~SQL.squish
        CASE
          WHEN cached_days_since_last_purchase IS NULL THEN 1
          WHEN cached_days_since_last_purchase BETWEEN 0 AND 30 THEN 5
          WHEN cached_days_since_last_purchase BETWEEN 31 AND 60 THEN 4
          WHEN cached_days_since_last_purchase BETWEEN 61 AND 90 THEN 3
          WHEN cached_days_since_last_purchase BETWEEN 91 AND 180 THEN 2
          ELSE 1
        END as recency_score
      SQL
    end

    def calculate_frequency_score_sql
      <<~SQL.squish
        CASE
          WHEN cached_purchase_frequency >= 10 THEN 5
          WHEN cached_purchase_frequency BETWEEN 6 AND 9 THEN 4
          WHEN cached_purchase_frequency BETWEEN 3 AND 5 THEN 3
          WHEN cached_purchase_frequency = 2 THEN 2
          ELSE 1
        END as frequency_score
      SQL
    end

    def calculate_monetary_score_sql(quartiles)
      <<~SQL.squish
        CASE
          WHEN cached_total_revenue >= #{quartiles[:q4]} THEN 5
          WHEN cached_total_revenue >= #{quartiles[:q3]} THEN 4
          WHEN cached_total_revenue >= #{quartiles[:q2]} THEN 3
          WHEN cached_total_revenue >= #{quartiles[:q1]} THEN 2
          ELSE 1
        END as monetary_score
      SQL
    end

    def empty_metrics_summary
      {
        total_customers: 0,
        active_customers: 0,
        avg_clv: 0,
        arpc: 0,
        repeat_customer_rate: 0,
        avg_purchase_frequency: 0,
        avg_days_between_purchases: 0
      }
    end
  end
end
