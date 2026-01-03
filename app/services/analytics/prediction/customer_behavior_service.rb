# frozen_string_literal: true

module Analytics
  module Prediction
    # Service for predicting customer behavior patterns
    # Analyzes purchase history to predict future actions
    class CustomerBehaviorService
      include Analytics::Concerns::StatisticalMethods
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Predict customer's next purchase date
      # @param customer [TenantCustomer] Customer to analyze
      # @return [Hash, nil] Prediction hash or nil if insufficient data
      def predict_next_purchase(customer)
        purchases = fetch_customer_purchases(customer)
        return nil if purchases.count < 2

        intervals = calculate_purchase_intervals(purchases)
        avg_interval = intervals.sum / intervals.count.to_f
        last_purchase = purchases.last

        {
          customer_id: customer.id,
          customer_name: customer.full_name,
          last_purchase: last_purchase,
          avg_interval_days: avg_interval.round(1),
          predicted_next_purchase: last_purchase + avg_interval.days,
          confidence: calculate_prediction_confidence(intervals)
        }
      end

      private

      def fetch_customer_purchases(customer)
        # Combine bookings and orders into a single timeline
        (customer.bookings.pluck(:created_at) + customer.orders.pluck(:created_at)).sort
      end

      def calculate_purchase_intervals(purchases)
        intervals = []
        (1...purchases.length).each do |i|
          intervals << (purchases[i] - purchases[i - 1]).to_i / 1.day
        end
        intervals
      end

      def calculate_prediction_confidence(intervals)
        return 'low' if intervals.count < 3

        avg = calculate_average(intervals)
        variance = intervals.sum { |i| (i - avg) ** 2 } / intervals.count.to_f
        std_dev = Math.sqrt(variance)
        coefficient_of_variation = (std_dev / avg) * 100

        case coefficient_of_variation
        when 0..25 then 'high'
        when 26..50 then 'medium'
        else 'low'
        end
      end
    end
  end
end
