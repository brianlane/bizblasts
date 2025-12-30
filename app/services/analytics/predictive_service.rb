# frozen_string_literal: true

module Analytics
  # Service for predictive analytics and intelligent forecasting
  # Uses statistical methods and rule-based algorithms
  # Can be enhanced with ML models (Rumale, TensorFlow.rb) in the future
  class PredictiveService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Demand forecasting by service (next 30 days)
    def forecast_service_demand(service_id, days_ahead = 30)
      service = business.services.find(service_id)

      # Historical data (last 90 days)
      historical_bookings = service.bookings
                                   .where(created_at: 90.days.ago..Time.current)
                                   .group_by_day(:created_at)
                                   .count

      # Calculate daily average and trend
      daily_avg = calculate_average(historical_bookings.values)
      trend = calculate_trend(historical_bookings.values)
      seasonality_factor = calculate_seasonality_factor(historical_bookings)

      # Forecast for each day
      forecast_days = (1..days_ahead).map do |day_offset|
        base_forecast = daily_avg + (trend * day_offset)
        adjusted_forecast = base_forecast * seasonality_factor

        {
          date: day_offset.days.from_now.to_date,
          forecasted_bookings: [adjusted_forecast.round, 1].max,
          confidence_level: calculate_confidence_level(historical_bookings.values)
        }
      end

      {
        service_id: service.id,
        service_name: service.name,
        historical_avg: daily_avg.round(2),
        trend_direction: trend > 0 ? 'increasing' : trend < 0 ? 'decreasing' : 'stable',
        forecast: forecast_days
      }
    end

    # Optimal pricing recommendations based on demand and competition
    def optimal_pricing_recommendations(service_id)
      service = business.services.find(service_id)
      current_price = service.price

      # Historical booking data at current price
      recent_bookings = service.bookings.where(created_at: 30.days.ago..Time.current)
      booking_rate = recent_bookings.count / 30.0

      # Calculate price elasticity estimate
      elasticity = estimate_price_elasticity(service)

      # Generate pricing scenarios
      scenarios = []

      [-20, -10, -5, 0, 5, 10, 20].each do |percentage_change|
        new_price = current_price * (1 + percentage_change / 100.0)
        demand_change = -elasticity * percentage_change # Negative because demand decreases when price increases

        estimated_bookings = [booking_rate * (1 + demand_change / 100.0), 0].max
        estimated_revenue = estimated_bookings * new_price * 30 # Monthly revenue

        scenarios << {
          price_change: percentage_change,
          new_price: new_price.round(2),
          estimated_monthly_bookings: estimated_bookings.round(1),
          estimated_monthly_revenue: estimated_revenue.round(2),
          revenue_change: ((estimated_revenue - (booking_rate * current_price * 30)) / (booking_rate * current_price * 30) * 100).round(1)
        }
      end

      # Find optimal price (max revenue)
      optimal = scenarios.max_by { |s| s[:estimated_monthly_revenue] }

      {
        service_id: service.id,
        service_name: service.name,
        current_price: current_price,
        current_monthly_bookings: booking_rate.round(1),
        optimal_price: optimal[:new_price],
        optimal_monthly_bookings: optimal[:estimated_monthly_bookings],
        revenue_increase_potential: optimal[:revenue_change],
        scenarios: scenarios
      }
    end

    # Anomaly detection in bookings, revenue, or inventory
    def detect_anomalies(metric_type, period = 30.days)
      case metric_type
      when :bookings
        detect_booking_anomalies(period)
      when :revenue
        detect_revenue_anomalies(period)
      when :inventory
        detect_inventory_anomalies(period)
      else
        []
      end
    end

    # Predict customer next purchase date
    def predict_next_purchase(customer)
      purchases = (customer.bookings.pluck(:created_at) + customer.orders.pluck(:created_at)).sort

      return nil if purchases.count < 2

      # Calculate average days between purchases
      intervals = []
      (1...purchases.length).each do |i|
        intervals << (purchases[i] - purchases[i-1]).to_i / 1.day
      end

      avg_interval = intervals.sum / intervals.count.to_f
      last_purchase = purchases.last

      predicted_date = last_purchase + avg_interval.days

      {
        customer_id: customer.id,
        customer_name: customer.full_name,
        last_purchase: last_purchase,
        avg_interval_days: avg_interval.round(1),
        predicted_next_purchase: predicted_date,
        confidence: calculate_prediction_confidence(intervals)
      }
    end

    # Staff scheduling optimization suggestions
    def optimize_staff_scheduling(date = Date.current)
      # Get historical booking patterns for this day of week
      day_of_week = date.wday
      historical_data = business.bookings
                                .where('EXTRACT(DOW FROM start_time) = ?', day_of_week)
                                .where(created_at: 90.days.ago..Time.current)
                                .group_by_hour(:start_time)
                                .count

      # Calculate required staff per hour
      recommendations = (8..20).map do |hour| # 8am to 8pm
        expected_bookings = historical_data["#{hour}:00"] || 0
        avg_service_duration = 60 # minutes

        # Estimate staff needed (each staff can handle 1 booking per hour on average)
        staff_needed = (expected_bookings * (avg_service_duration / 60.0)).ceil

        {
          hour: "#{hour}:00",
          expected_bookings: expected_bookings,
          recommended_staff: [staff_needed, 1].max
        }
      end

      {
        date: date,
        day_of_week: Date::DAYNAMES[day_of_week],
        recommendations: recommendations,
        peak_hour: recommendations.max_by { |r| r[:expected_bookings] }[:hour],
        slowest_hour: recommendations.min_by { |r| r[:expected_bookings] }[:hour]
      }
    end

    # Inventory restock prediction
    def predict_restock_needs(days_ahead = 30)
      products = business.products.includes(:product_variants)

      predictions = []

      products.each do |product|
        product.product_variants.each do |variant|
          next unless variant.stock_quantity && variant.stock_quantity > 0

          # Calculate daily sales rate
          daily_sales = calculate_daily_sales_rate(variant, 30.days)
          next if daily_sales.zero?

          days_until_stockout = variant.stock_quantity / daily_sales

          if days_until_stockout <= days_ahead
            restock_date = days_until_stockout.days.from_now.to_date

            predictions << {
              product_name: product.name,
              variant_name: variant.name,
              current_stock: variant.stock_quantity,
              daily_sales_rate: daily_sales.round(2),
              days_until_stockout: days_until_stockout.round(1),
              predicted_stockout_date: restock_date,
              recommended_restock_quantity: (daily_sales * 30).ceil,
              urgency: days_until_stockout <= 7 ? 'high' : days_until_stockout <= 14 ? 'medium' : 'low'
            }
          end
        end
      end

      predictions.sort_by { |p| p[:days_until_stockout] }
    end

    # Revenue prediction for next period
    def predict_revenue(days_ahead = 30)
      # Get historical revenue data
      historical_revenue = (0..89).map do |days_ago|
        date = days_ago.days.ago.to_date
        business.payments
                .where(created_at: date.beginning_of_day..date.end_of_day, status: 'completed')
                .sum(:amount).to_f
      end.reverse

      # Calculate trend using linear regression
      daily_avg = calculate_average(historical_revenue)
      trend = calculate_trend(historical_revenue)

      # Forecast each day
      forecast_days = (1..days_ahead).map do |day_offset|
        predicted_revenue = daily_avg + (trend * day_offset)

        {
          date: day_offset.days.from_now.to_date,
          predicted_revenue: [predicted_revenue, 0].max.round(2)
        }
      end

      total_predicted = forecast_days.sum { |f| f[:predicted_revenue] }

      {
        historical_daily_avg: daily_avg.round(2),
        trend_direction: trend > 0 ? 'increasing' : trend < 0 ? 'decreasing' : 'stable',
        predicted_total: total_predicted.round(2),
        forecast: forecast_days
      }
    end

    private

    def calculate_average(values)
      return 0 if values.empty?
      values.sum / values.count.to_f
    end

    def calculate_trend(values)
      return 0 if values.length < 2

      n = values.length
      x_sum = (0...n).sum
      y_sum = values.sum
      xy_sum = values.each_with_index.sum { |y, x| x * y }
      x_squared_sum = (0...n).sum { |x| x * x }

      # Linear regression slope
      numerator = (n * xy_sum - x_sum * y_sum).to_f
      denominator = (n * x_squared_sum - x_sum * x_sum).to_f

      denominator.zero? ? 0 : numerator / denominator
    end

    def calculate_seasonality_factor(historical_data)
      # Simple day-of-week seasonality
      # Could be enhanced with more sophisticated seasonal decomposition
      1.0 # Placeholder - returns neutral factor
    end

    def calculate_confidence_level(values)
      return 'low' if values.count < 30

      # Calculate coefficient of variation
      avg = calculate_average(values)
      return 'low' if avg.zero?

      variance = values.sum { |v| (v - avg) ** 2 } / values.count.to_f
      std_dev = Math.sqrt(variance)
      cv = (std_dev / avg) * 100

      case cv
      when 0..20 then 'high'
      when 21..40 then 'medium'
      else 'low'
      end
    end

    def estimate_price_elasticity(service)
      # Simplified elasticity estimate
      # In reality, would need A/B testing or historical price change data
      # Typical service elasticity ranges from -0.5 to -2.0
      -1.0 # Moderate elasticity estimate
    end

    def calculate_daily_sales_rate(variant, period)
      total_sold = business.orders
                          .joins(:line_items)
                          .where(created_at: period.ago..Time.current)
                          .where(line_items: { product_variant_id: variant.id })
                          .sum('line_items.quantity').to_f

      days = (period / 1.day).to_i

      total_sold / days
    end

    def detect_booking_anomalies(period)
      daily_bookings = business.bookings
                               .where(created_at: period.ago..Time.current)
                               .group_by_day(:created_at)
                               .count

      detect_statistical_anomalies(daily_bookings, 'bookings')
    end

    def detect_revenue_anomalies(period)
      daily_revenue = business.payments
                              .where(created_at: period.ago..Time.current, status: 'completed')
                              .group_by_day(:created_at)
                              .sum(:amount)

      detect_statistical_anomalies(daily_revenue, 'revenue')
    end

    def detect_inventory_anomalies(period)
      daily_adjustments = business.stock_movements
                                  .where(created_at: period.ago..Time.current, movement_type: 'adjustment')
                                  .group_by_day(:created_at)
                                  .count

      detect_statistical_anomalies(daily_adjustments, 'inventory_adjustments')
    end

    def detect_statistical_anomalies(data_hash, metric_name)
      values = data_hash.values.map(&:to_f)
      return [] if values.count < 7

      avg = calculate_average(values)
      variance = values.sum { |v| (v - avg) ** 2 } / values.count.to_f
      std_dev = Math.sqrt(variance)

      # Detect values beyond 2 standard deviations
      anomalies = []
      data_hash.each do |date, value|
        z_score = (value - avg) / std_dev
        if z_score.abs > 2
          anomalies << {
            date: date,
            metric: metric_name,
            value: value.to_f.round(2),
            expected_range: "#{(avg - 2*std_dev).round(2)} - #{(avg + 2*std_dev).round(2)}",
            severity: z_score.abs > 3 ? 'high' : 'medium',
            direction: z_score > 0 ? 'above' : 'below'
          }
        end
      end

      anomalies
    end

    def calculate_prediction_confidence(intervals)
      return 'low' if intervals.count < 3

      avg = calculate_average(intervals)
      variance = intervals.sum { |i| (i - avg) ** 2 } / intervals.count.to_f
      std_dev = Math.sqrt(variance)
      cv = (std_dev / avg) * 100

      case cv
      when 0..25 then 'high'
      when 26..50 then 'medium'
      else 'low'
      end
    end
  end
end
