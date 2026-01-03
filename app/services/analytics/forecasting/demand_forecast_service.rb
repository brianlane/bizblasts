# frozen_string_literal: true

module Analytics
  module Forecasting
    # Service for forecasting service demand
    # Predicts future booking demand based on historical patterns
    class DemandForecastService
      include Analytics::Concerns::StatisticalMethods
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Forecast demand for a specific service
      # @param service_id [Integer] The service to forecast
      # @param days_ahead [Integer] Number of days to forecast (default: 30)
      # @return [Hash] Forecast data or error hash
      def forecast_service_demand(service_id, days_ahead = 30)
        service = business.services.find_by(id: service_id)
        return { error: 'Service not found' } unless service

        historical_bookings = fetch_historical_bookings(service)
        return { error: 'Insufficient historical data' } if historical_bookings.values.size < 7

        daily_avg = calculate_average(historical_bookings.values)
        return { error: 'Cannot calculate forecast from zero bookings' } if daily_avg.zero?

        trend = calculate_trend(historical_bookings.values)
        seasonality_factor = calculate_seasonality_factor(historical_bookings)

        forecast_days = generate_forecast(daily_avg, trend, seasonality_factor, days_ahead)

        {
          service_id: service.id,
          service_name: service.name,
          historical_avg: daily_avg.round(2),
          trend_direction: determine_trend_direction(trend),
          forecast: forecast_days
        }
      rescue StandardError => e
        Rails.logger.error "[DemandForecastService] Error: #{e.message}"
        { error: 'An error occurred while generating forecast' }
      end

      private

      def fetch_historical_bookings(service)
        service.bookings
               .where(created_at: 90.days.ago..Time.current)
               .group_by_day(:created_at)
               .count
      end

      def calculate_seasonality_factor(historical_data)
        # Simple day-of-week seasonality
        # Could be enhanced with more sophisticated seasonal decomposition
        1.0 # Placeholder - returns neutral factor
      end

      def generate_forecast(daily_avg, trend, seasonality_factor, days_ahead)
        (1..days_ahead).map do |day_offset|
          base_forecast = daily_avg + (trend * day_offset)
          adjusted_forecast = base_forecast * seasonality_factor

          {
            date: day_offset.days.from_now.to_date,
            forecasted_bookings: [adjusted_forecast.round, 1].max,
            confidence_level: 75
          }
        end
      end

      def determine_trend_direction(trend)
        return 'increasing' if trend > 0
        return 'decreasing' if trend < 0
        'stable'
      end
    end
  end
end
