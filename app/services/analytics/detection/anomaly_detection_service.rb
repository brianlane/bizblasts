# frozen_string_literal: true

module Analytics
  module Detection
    # Service for detecting anomalies in business metrics
    # Uses statistical methods to identify unusual patterns
    class AnomalyDetectionService
      include Analytics::Concerns::StatisticalMethods
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Detect anomalies in various metrics
      # @param metric_type [Symbol] Type of metric (:bookings, :revenue, :inventory)
      # @param period [ActiveSupport::Duration] Time period to analyze (default: 30 days)
      # @return [Array<Hash>] Array of detected anomalies
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

      private

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
    end
  end
end
