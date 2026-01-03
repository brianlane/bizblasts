# frozen_string_literal: true

module Analytics
  module Optimization
    # Service for staff scheduling optimization
    # Provides recommendations based on historical booking patterns
    class StaffSchedulingService
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Generate staff scheduling recommendations for a specific date
      # @param date [Date] Date to optimize for (default: today)
      # @return [Hash] Scheduling recommendations
      def optimize_staff_scheduling(date = Date.current)
        day_of_week = date.wday
        historical_data = fetch_historical_bookings(day_of_week)

        recommendations = generate_hourly_recommendations(historical_data)
        peak_hour = find_peak_hour(recommendations)
        slowest_hour = find_slowest_hour(recommendations)

        {
          date: date,
          day_of_week: Date::DAYNAMES[day_of_week],
          recommendations: recommendations,
          peak_hour: peak_hour,
          slowest_hour: slowest_hour
        }
      end

      private

      def fetch_historical_bookings(day_of_week)
        business.bookings
                .where('EXTRACT(DOW FROM start_time) = ?', day_of_week)
                .where(created_at: 90.days.ago..Time.current)
                .group_by_hour(:start_time)
                .count
      end

      def generate_hourly_recommendations(historical_data)
        (8..20).map do |hour| # Business hours: 8am to 8pm
          expected_bookings = historical_data["#{hour}:00"] || 0
          avg_service_duration = 60 # minutes

          # Each staff member can handle ~1 booking per hour on average
          staff_needed = (expected_bookings * (avg_service_duration / 60.0)).ceil

          {
            hour: "#{hour}:00",
            expected_bookings: expected_bookings,
            recommended_staff: [staff_needed, 1].max
          }
        end
      end

      def find_peak_hour(recommendations)
        recommendations.max_by { |r| r[:expected_bookings] }[:hour]
      end

      def find_slowest_hour(recommendations)
        recommendations.min_by { |r| r[:expected_bookings] }[:hour]
      end
    end
  end
end
