# frozen_string_literal: true

module Analytics
  module Concerns
    # Shared statistical methods for analytics services
    # Provides common mathematical and statistical calculations
    module StatisticalMethods
      # Calculate average of values
      # @param values [Array<Numeric>] Values to average
      # @return [Float] Average value, 0 if empty
      def calculate_average(values)
        return 0 if values.empty?
        values.sum / values.count.to_f
      end

      # Calculate linear regression trend
      # @param values [Array<Numeric>] Time series values
      # @return [Float] Trend slope (positive = increasing, negative = decreasing)
      def calculate_trend(values)
        return 0 if values.length < 2

        n = values.length
        x_sum = (0...n).sum
        y_sum = values.sum
        xy_sum = values.each_with_index.sum { |y, x| x * y }
        x_squared_sum = (0...n).sum { |x| x * x }

        # Linear regression slope: (n * Σxy - Σx * Σy) / (n * Σx² - (Σx)²)
        numerator = (n * xy_sum - x_sum * y_sum).to_f
        denominator = (n * x_squared_sum - x_sum * x_sum).to_f

        denominator.zero? ? 0 : numerator / denominator
      end

      # Calculate confidence level based on coefficient of variation
      # @param values [Array<Numeric>] Time series values
      # @return [String] Confidence level: 'high', 'medium', or 'low'
      def calculate_confidence_level(values)
        return 'low' if values.count < 30

        avg = calculate_average(values)
        return 'low' if avg.zero?

        variance = values.sum { |v| (v - avg) ** 2 } / values.count.to_f
        std_dev = Math.sqrt(variance)
        coefficient_of_variation = (std_dev / avg) * 100

        case coefficient_of_variation
        when 0..20 then 'high'
        when 21..40 then 'medium'
        else 'low'
        end
      end

      # Calculate standard deviation
      # @param values [Array<Numeric>] Values
      # @return [Float] Standard deviation
      def calculate_std_dev(values)
        return 0 if values.empty?

        avg = calculate_average(values)
        variance = values.sum { |v| (v - avg) ** 2 } / values.count.to_f
        Math.sqrt(variance)
      end

      # Calculate z-score for a value
      # @param value [Numeric] Value to score
      # @param mean [Numeric] Mean of distribution
      # @param std_dev [Numeric] Standard deviation
      # @return [Float] Z-score
      def calculate_z_score(value, mean, std_dev)
        return 0 if std_dev.zero?
        (value - mean) / std_dev
      end

      # Detect statistical anomalies using z-score
      # @param data_hash [Hash] Hash of date => value
      # @param metric_name [String] Name of metric for reporting
      # @param threshold [Float] Z-score threshold (default: 2.0)
      # @return [Array<Hash>] Array of anomalies
      def detect_statistical_anomalies(data_hash, metric_name, threshold: 2.0)
        values = data_hash.values.map(&:to_f)
        return [] if values.count < 7

        avg = calculate_average(values)
        std_dev = calculate_std_dev(values)
        return [] if std_dev.zero?

        anomalies = []
        data_hash.each do |date, value|
          z_score = calculate_z_score(value.to_f, avg, std_dev)

          if z_score.abs > threshold
            # Calculate deviation percentage from expected average
            deviation_percentage = avg.zero? ? 0 : ((value.to_f - avg).abs / avg * 100).round(1)

            anomalies << {
              date: date,
              metric: metric_name,
              value: value.to_f.round(2),
              expected_range: "#{(avg - threshold * std_dev).round(2)} - #{(avg + threshold * std_dev).round(2)}",
              severity: z_score.abs > 3 ? 'high' : 'medium',
              direction: z_score > 0 ? 'above' : 'below',
              z_score: z_score.round(2),
              deviation_percentage: deviation_percentage
            }
          end
        end

        anomalies
      end
    end
  end
end
