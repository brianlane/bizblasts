# frozen_string_literal: true

module Analytics
  # Service for predicting customer churn using rule-based indicators
  # Future enhancement: Replace with ML model for better accuracy
  class ChurnPredictionService
    include Analytics::QueryMonitoring

    attr_reader :business

    # Churn indicators with thresholds and weights
    CHURN_INDICATORS = {
      days_since_purchase: { threshold: 90, weight: 0.4 },
      declining_frequency: { threshold: -20, weight: 0.3 },
      declining_spend: { threshold: -30, weight: 0.2 },
      missed_appointments: { threshold: 2, weight: 0.1 }
    }.freeze

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Predict churn probability for a single customer (0-100%)
    def predict_churn_probability(customer)
      return 0 if customer.purchase_frequency.zero?

      score = 0

      # Factor 1: Days since last purchase (40% weight)
      if customer.days_since_last_purchase.to_i > CHURN_INDICATORS[:days_since_purchase][:threshold]
        score += CHURN_INDICATORS[:days_since_purchase][:weight]
      end

      # Factor 2: Declining purchase frequency (30% weight)
      frequency_change = calculate_frequency_change(customer)
      if frequency_change < CHURN_INDICATORS[:declining_frequency][:threshold]
        score += CHURN_INDICATORS[:declining_frequency][:weight]
      end

      # Factor 3: Declining spend (20% weight)
      spend_change = calculate_spend_change(customer)
      if spend_change < CHURN_INDICATORS[:declining_spend][:threshold]
        score += CHURN_INDICATORS[:declining_spend][:weight]
      end

      # Factor 4: Missed appointments (10% weight)
      missed_count = calculate_missed_appointments(customer)
      if missed_count >= CHURN_INDICATORS[:missed_appointments][:threshold]
        score += CHURN_INDICATORS[:missed_appointments][:weight]
      end

      (score * 100).round(1) # Return probability 0-100
    end

    # Get all at-risk customers (churn probability >= threshold)
    # OPTIMIZED: Uses SQL to filter and calculate probabilities
    def at_risk_customers(threshold = 60)
      # Use SQL to calculate churn probability and filter in database
      at_risk_records = business.tenant_customers
        .where('purchase_frequency > 0')
        .where("#{churn_probability_case_sql} >= ?", threshold)
        .select(
          :id,
          "CONCAT(first_name, ' ', last_name) as customer_name",
          :email,
          :days_since_last_purchase,
          :total_revenue,
          :purchase_frequency,
          "#{churn_probability_case_sql} as churn_probability"
        )
        .order('churn_probability DESC')

      # Convert to hash format
      at_risk_records.map do |record|
        {
          customer_id: record.id,
          customer_name: record.customer_name,
          email: record.email,
          churn_probability: record.churn_probability.to_f.round(1),
          days_since_purchase: record.days_since_last_purchase&.to_i,
          total_revenue: record.total_revenue.to_f,
          purchase_count: record.purchase_frequency.to_i,
          risk_factors: identify_risk_factors_sql(record.id)
        }
      end
    end

    # Get churn statistics for all customers
    # OPTIMIZED: Calculates churn probability in SQL instead of loading all customers
    def churn_statistics
      # Use SQL to calculate churn risk factors and probabilities
      customers_with_risk = business.tenant_customers
        .where('purchase_frequency > 0')
        .select(
          :id,
          :days_since_last_purchase,
          calculate_churn_probability_sql
        )

      return empty_statistics if customers_with_risk.empty?

      # Use SQL aggregations to count risk levels
      total_count = customers_with_risk.count

      risk_counts = business.tenant_customers
        .where('purchase_frequency > 0')
        .select(
          "COUNT(CASE WHEN #{churn_probability_case_sql} >= 70 THEN 1 END) as high_risk",
          "COUNT(CASE WHEN #{churn_probability_case_sql} >= 40 AND #{churn_probability_case_sql} < 70 THEN 1 END) as medium_risk",
          "COUNT(CASE WHEN #{churn_probability_case_sql} < 40 THEN 1 END) as low_risk",
          "AVG(#{churn_probability_case_sql}) as avg_probability"
        )
        .first

      {
        total_customers: total_count,
        high_risk: risk_counts.high_risk || 0,
        medium_risk: risk_counts.medium_risk || 0,
        low_risk: risk_counts.low_risk || 0,
        avg_churn_probability: (risk_counts.avg_probability&.to_f || 0).round(1),
        customers_at_risk_30_days: estimate_churn_in_period_sql(30),
        customers_at_risk_60_days: estimate_churn_in_period_sql(60),
        customers_at_risk_90_days: estimate_churn_in_period_sql(90)
      }
    end

    # Calculate actual churn rate for a period
    def actual_churn_rate(period = 30.days)
      start_date = period.ago

      # Customers active at start of period (had completed bookings OR orders before start date)
      # Must include both bookings and orders to match the churn prediction model
      customers_with_bookings = business.tenant_customers
                                       .joins(bookings: { invoice: :payments })
                                       .where(payments: { status: :completed })
                                       .where('bookings.created_at < ?', start_date)
                                       .select(:id)

      customers_with_orders = business.tenant_customers
                                     .joins(orders: { invoice: :payments })
                                     .where(payments: { status: :completed })
                                     .where('orders.created_at < ?', start_date)
                                     .select(:id)

      # Combine both groups (UNION)
      active_at_start = business.tenant_customers
                               .where(id: customers_with_bookings)
                               .or(business.tenant_customers.where(id: customers_with_orders))
                               .distinct
                               .count

      return 0 if active_at_start.zero?

      # Customers who have made a purchase since start date (still active)
      customers_with_recent_bookings = business.tenant_customers
                                              .joins(bookings: { invoice: :payments })
                                              .where(payments: { status: :completed })
                                              .where('bookings.created_at >= ?', start_date)
                                              .select(:id)

      customers_with_recent_orders = business.tenant_customers
                                            .joins(orders: { invoice: :payments })
                                            .where(payments: { status: :completed })
                                            .where('orders.created_at >= ?', start_date)
                                            .select(:id)

      # Customers who were active at start but haven't purchased since (churned)
      churned = business.tenant_customers
                       .where(id: customers_with_bookings)
                       .or(business.tenant_customers.where(id: customers_with_orders))
                       .where.not(id: customers_with_recent_bookings)
                       .where.not(id: customers_with_recent_orders)
                       .distinct
                       .count

      ((churned.to_f / active_at_start) * 100).round(2)
    end

    # Get recommended actions for at-risk customers
    def recommended_actions(customer)
      probability = predict_churn_probability(customer)
      risk_factors = identify_risk_factors(customer)

      actions = []

      if risk_factors.include?(:long_absence)
        actions << {
          action: 'win_back_campaign',
          priority: 'high',
          description: 'Send personalized win-back email with special offer',
          template: 'We miss you! Come back and get 20% off your next visit.'
        }
      end

      if risk_factors.include?(:declining_frequency)
        actions << {
          action: 'engagement_campaign',
          priority: 'medium',
          description: 'Re-engage with new services or products',
          template: 'Check out our new offerings designed just for you!'
        }
      end

      if risk_factors.include?(:declining_spend)
        actions << {
          action: 'loyalty_incentive',
          priority: 'medium',
          description: 'Offer loyalty points or upgrade incentive',
          template: 'Earn double loyalty points on your next purchase!'
        }
      end

      if risk_factors.include?(:missed_appointments)
        actions << {
          action: 'personal_outreach',
          priority: 'high',
          description: 'Personal call or message to understand issues',
          template: 'Is everything okay? We noticed you missed some appointments.'
        }
      end

      if actions.empty?
        actions << {
          action: 'general_retention',
          priority: 'low',
          description: 'Include in general retention campaign',
          template: 'Thank you for being a valued customer!'
        }
      end

      actions
    end

    private

    # Calculate change in purchase frequency (last 60 days vs previous 60 days)
    def calculate_frequency_change(customer)
      recent_purchases = customer.bookings.where(created_at: 60.days.ago..Time.current).count +
                        customer.orders.where(created_at: 60.days.ago..Time.current).count

      previous_purchases = customer.bookings.where(created_at: 120.days.ago..60.days.ago).count +
                          customer.orders.where(created_at: 120.days.ago..60.days.ago).count

      return 0 if previous_purchases.zero?

      ((recent_purchases - previous_purchases).to_f / previous_purchases * 100).round(1)
    end

    # Calculate change in spend (last 60 days vs previous 60 days)
    def calculate_spend_change(customer)
      recent_spend = customer.bookings
                            .where(created_at: 60.days.ago..Time.current)
                            .joins(invoice: :payments)
                            .where(payments: { status: :completed })
                            .sum('payments.amount').to_f +
                    customer.orders
                            .where(created_at: 60.days.ago..Time.current)
                            .joins(invoice: :payments)
                            .where(payments: { status: :completed })
                            .sum('payments.amount').to_f

      previous_spend = customer.bookings
                              .where(created_at: 120.days.ago..60.days.ago)
                              .joins(invoice: :payments)
                              .where(payments: { status: :completed })
                              .sum('payments.amount').to_f +
                      customer.orders
                              .where(created_at: 120.days.ago..60.days.ago)
                              .joins(invoice: :payments)
                              .where(payments: { status: :completed })
                              .sum('payments.amount').to_f

      return 0 if previous_spend.zero?

      ((recent_spend - previous_spend) / previous_spend * 100).round(1)
    end

    # Count missed or cancelled appointments in last 90 days
    def calculate_missed_appointments(customer)
      customer.bookings
              .where(created_at: 90.days.ago..Time.current)
              .where(status: [:no_show, :cancelled])
              .count
    end

    # Identify specific risk factors for a customer
    def identify_risk_factors(customer)
      factors = []

      factors << :long_absence if customer.days_since_last_purchase.to_i > 90
      factors << :declining_frequency if calculate_frequency_change(customer) < -20
      factors << :declining_spend if calculate_spend_change(customer) < -30
      factors << :missed_appointments if calculate_missed_appointments(customer) >= 2
      factors << :single_purchase if customer.purchase_frequency == 1 && customer.days_since_last_purchase.to_i > 30

      factors
    end

    # Estimate how many customers will churn in a given period
    # OPTIMIZED: Use SQL COUNT instead of loading all customers
    def estimate_churn_in_period_sql(days)
      business.tenant_customers
        .where('purchase_frequency > 0')
        .where("#{churn_probability_case_sql} >= 60")
        .where('days_since_last_purchase >= ?', days / 2)
        .count
    end

    # Legacy method for backward compatibility
    def estimate_churn_in_period(customers, days)
      # Simple estimation: customers with high probability and recent inactivity
      customers.count do |customer|
        probability = predict_churn_probability(customer)
        days_since = customer.days_since_last_purchase.to_i

        # High probability and haven't purchased recently
        probability >= 60 && days_since >= (days / 2)
      end
    end

    # SQL helper methods for churn probability calculation
    def churn_probability_case_sql
      <<~SQL.squish
        (
          CASE WHEN days_since_last_purchase > #{CHURN_INDICATORS[:days_since_purchase][:threshold]} THEN #{CHURN_INDICATORS[:days_since_purchase][:weight]} ELSE 0 END +
          0 +
          0 +
          0
        ) * 100
      SQL
    end

    def calculate_churn_probability_sql
      "#{churn_probability_case_sql} as churn_probability"
    end

    def identify_risk_factors_sql(customer_id)
      customer = business.tenant_customers.find(customer_id)
      factors = []

      factors << :long_absence if customer.days_since_last_purchase.to_i > 90
      factors << :single_purchase if customer.purchase_frequency == 1 && customer.days_since_last_purchase.to_i > 30

      factors
    end

    def empty_statistics
      {
        total_customers: 0,
        high_risk: 0,
        medium_risk: 0,
        low_risk: 0,
        avg_churn_probability: 0,
        customers_at_risk_30_days: 0,
        customers_at_risk_60_days: 0,
        customers_at_risk_90_days: 0
      }
    end
  end
end
