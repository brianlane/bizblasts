# frozen_string_literal: true

module Analytics
  module Pricing
    # Service for optimal pricing recommendations
    # Analyzes demand elasticity and suggests pricing strategies
    class OptimizationService
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Generate optimal pricing recommendations for a service
      # @param service_id [Integer] The service to analyze
      # @return [Hash] Pricing recommendations or error hash
      def optimal_pricing_recommendations(service_id)
        service = business.services.find_by(id: service_id)
        return { error: 'Service not found' } unless service

        current_price = service.price
        return { error: 'Service price not set' } if current_price.nil? || current_price.zero?

        booking_rate = calculate_booking_rate(service)
        elasticity = estimate_price_elasticity(service)

        scenarios = generate_pricing_scenarios(current_price, booking_rate, elasticity)
        optimal = find_optimal_scenario(scenarios)

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

      private

      def calculate_booking_rate(service)
        recent_bookings = service.bookings.where(created_at: 30.days.ago..Time.current)
        recent_bookings.count / 30.0
      end

      def estimate_price_elasticity(service)
        # Simplified elasticity estimate
        # In reality, would need A/B testing or historical price change data
        # Typical service elasticity ranges from -0.5 to -2.0
        -1.0 # Moderate elasticity estimate
      end

      def generate_pricing_scenarios(current_price, booking_rate, elasticity)
        scenarios = []

        [-20, -10, -5, 0, 5, 10, 20].each do |percentage_change|
          new_price = current_price * (1 + percentage_change / 100.0)
          demand_change = -elasticity * percentage_change

          estimated_bookings = [booking_rate * (1 + demand_change / 100.0), 0].max
          estimated_revenue = estimated_bookings * new_price * 30
          current_revenue = booking_rate * current_price * 30

          scenarios << {
            price_change: percentage_change,
            new_price: new_price.round(2),
            estimated_monthly_bookings: estimated_bookings.round(1),
            estimated_monthly_revenue: estimated_revenue.round(2),
            revenue_change: calculate_revenue_change_percent(estimated_revenue, current_revenue)
          }
        end

        scenarios
      end

      def calculate_revenue_change_percent(estimated_revenue, current_revenue)
        return 0 if current_revenue.zero?
        ((estimated_revenue - current_revenue) / current_revenue * 100).round(1)
      end

      def find_optimal_scenario(scenarios)
        scenarios.max_by { |s| s[:estimated_monthly_revenue] }
      end
    end
  end
end
