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
    # CLV = (Average Order Value × Purchase Frequency) × Customer Lifespan
    def calculate_clv(customer)
      return 0 if customer.purchase_frequency.zero?

      avg_order_value = customer.total_revenue / customer.purchase_frequency
      customer_lifespan_years = customer.lifespan_days / 365.0

      # Estimate future value based on historical patterns
      (avg_order_value * customer.purchase_frequency_per_year * customer_lifespan_years).round(2)
    end

    # Calculate Average Revenue Per Customer for a period
    def calculate_arpc(period = 30.days)
      customers_with_activity = business.tenant_customers
                                        .joins("LEFT JOIN bookings ON bookings.tenant_customer_id = tenant_customers.id")
                                        .joins("LEFT JOIN orders ON orders.tenant_customer_id = tenant_customers.id")
                                        .where("bookings.created_at >= ? OR orders.created_at >= ?", period.ago, period.ago)
                                        .distinct

      customer_count = customers_with_activity.count
      return 0 if customer_count.zero?

      total_revenue = calculate_total_revenue(period)
      (total_revenue / customer_count).round(2)
    end

    # RFM (Recency, Frequency, Monetary) Segmentation
    def customer_segments_rfm
      customers = business.tenant_customers.includes(:bookings, :orders)

      # Calculate RFM scores for all customers
      customer_data = customers.map do |customer|
        next if customer.purchase_frequency.zero? # Skip customers with no purchases

        {
          customer_id: customer.id,
          customer_name: customer.full_name,
          email: customer.email,
          recency_score: calculate_recency_score(customer),
          frequency_score: calculate_frequency_score(customer),
          monetary_score: calculate_monetary_score(customer)
        }
      end.compact

      # Assign segments based on RFM scores
      customer_data.map do |data|
        data.merge(segment: determine_segment(data[:recency_score], data[:frequency_score], data[:monetary_score]))
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
                                 customers.sum { |c|
                                   business.tenant_customers.find(c[:customer_id]).total_revenue
                                 }
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
    def customer_metrics_summary(period = 30.days)
      customers = business.tenant_customers.includes(:bookings, :orders)
      customers_with_purchases = customers.select { |c| c.purchase_frequency > 0 }

      return empty_metrics_summary if customers_with_purchases.empty?

      {
        total_customers: customers.count,
        active_customers: customers_with_purchases.count,
        avg_clv: customers_with_purchases.sum { |c| calculate_clv(c) } / customers_with_purchases.count,
        arpc: calculate_arpc(period),
        repeat_customer_rate: calculate_repeat_rate(customers),
        avg_purchase_frequency: customers_with_purchases.sum(&:purchase_frequency) / customers_with_purchases.count,
        avg_days_between_purchases: calculate_avg_days_between_purchases(customers_with_purchases)
      }
    end

    private

    def calculate_total_revenue(period)
      booking_revenue = business.bookings
                               .where(created_at: period.ago..Time.current)
                               .joins(invoice: :payments)
                               .where(payments: { status: :completed })
                               .sum('payments.amount')

      order_revenue = business.orders
                             .where(created_at: period.ago..Time.current)
                             .joins(:payments)
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

    def calculate_monetary_score(customer)
      revenue = customer.total_revenue

      # Use business-specific quartiles for more accurate scoring
      quartiles = calculate_revenue_quartiles

      case revenue
      when quartiles[:q4]..Float::INFINITY then 5
      when quartiles[:q3]...quartiles[:q4] then 4
      when quartiles[:q2]...quartiles[:q3] then 3
      when quartiles[:q1]...quartiles[:q2] then 2
      else 1
      end
    end

    def calculate_revenue_quartiles
      revenues = business.tenant_customers.map(&:total_revenue).sort
      return { q1: 0, q2: 0, q3: 0, q4: 0 } if revenues.empty?

      {
        q1: revenues[revenues.length / 4] || 0,
        q2: revenues[revenues.length / 2] || 0,
        q3: revenues[(revenues.length * 3) / 4] || 0,
        q4: revenues[(revenues.length * 9) / 10] || 0
      }
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

    def calculate_repeat_rate(customers)
      customers_with_purchases = customers.select { |c| c.purchase_frequency > 0 }
      return 0 if customers_with_purchases.empty?

      repeat_customers = customers_with_purchases.count { |c| c.purchase_frequency > 1 }
      ((repeat_customers.to_f / customers_with_purchases.count) * 100).round(2)
    end

    def calculate_avg_days_between_purchases(customers)
      intervals = customers.map(&:avg_days_between_purchases).compact
      return 0 if intervals.empty?

      (intervals.sum / intervals.count).round(0)
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
