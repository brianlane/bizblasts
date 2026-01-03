# frozen_string_literal: true

module Analytics
  module Inventory
    # Service for predicting inventory restock needs
    # Analyzes sales patterns to forecast stockouts
    class RestockPredictionService
      include Analytics::QueryMonitoring

      attr_reader :business

      self.query_threshold = 1.0

      def initialize(business)
        @business = business
      end

      # Predict when products need restocking
      # @param days_ahead [Integer] Forecast period in days (default: 30)
      # @return [Array<Hash>] Array of restock predictions, sorted by urgency
      def predict_restock_needs(days_ahead = 30)
        products = business.products.includes(:product_variants)
        predictions = []

        products.each do |product|
          product.product_variants.each do |variant|
            prediction = analyze_variant(variant, days_ahead, product.name)
            predictions << prediction if prediction
          end
        end

        predictions.sort_by { |p| p[:days_until_stockout] }
      end

      private

      def analyze_variant(variant, days_ahead, product_name)
        return nil unless variant.stock_quantity && variant.stock_quantity > 0

        daily_sales = calculate_daily_sales_rate(variant, 30.days)
        return nil if daily_sales.zero?

        days_until_stockout = variant.stock_quantity / daily_sales

        return nil if days_until_stockout > days_ahead

        {
          product_name: product_name,
          variant_name: variant.name,
          current_stock: variant.stock_quantity,
          daily_sales_rate: daily_sales.round(2),
          days_until_stockout: days_until_stockout.round(1),
          predicted_stockout_date: days_until_stockout.days.from_now.to_date,
          recommended_restock_quantity: (daily_sales * 30).ceil,
          cost_price: variant.cost_price || 0,
          urgency: determine_urgency(days_until_stockout)
        }
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

      def determine_urgency(days_until_stockout)
        return 'critical' if days_until_stockout <= 3
        return 'high' if days_until_stockout <= 7
        return 'medium' if days_until_stockout <= 14
        'low'
      end
    end
  end
end
