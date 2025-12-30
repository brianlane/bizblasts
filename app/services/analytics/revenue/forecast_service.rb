# frozen_string_literal: true

module Analytics
  module Revenue
    # Service for revenue forecasting
    # Predicts future revenue based on historical trends
    class ForecastService
      include Analytics::Concerns::StatisticalMethods
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Predict revenue for the next period
      # @param days_ahead [Integer] Number of days to forecast (default: 30)
      # @return [Hash] Revenue forecast data
      def predict_revenue(days_ahead = 30)
        historical_revenue = fetch_historical_revenue
        daily_avg = calculate_average(historical_revenue)
        trend = calculate_trend(historical_revenue)

        forecast_days = generate_daily_forecasts(daily_avg, trend, days_ahead)
        total_predicted = forecast_days.sum { |f| f[:predicted_revenue] }

        {
          historical_daily_avg: daily_avg.round(2),
          trend_direction: determine_trend_direction(trend),
          predicted_total: total_predicted.round(2),
          forecast: forecast_days
        }
      end

      private

      def fetch_historical_revenue
        # Get last 90 days of revenue data
        (0..89).map do |days_ago|
          date = days_ago.days.ago.to_date
          business.payments
                  .where(created_at: date.beginning_of_day..date.end_of_day, status: 'completed')
                  .sum(:amount).to_f
        end.reverse
      end

      def generate_daily_forecasts(daily_avg, trend, days_ahead)
        (1..days_ahead).map do |day_offset|
          predicted_revenue = daily_avg + (trend * day_offset)

          {
            date: day_offset.days.from_now.to_date,
            predicted_revenue: [predicted_revenue, 0].max.round(2)
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
