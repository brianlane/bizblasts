# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for inventory intelligence and stock analytics
    class InventoryController < BusinessManager::BaseController
      before_action :set_inventory_service

      def index
        @period = params[:period]&.to_sym || :last_30_days
        period_days = period_to_days(@period)

        @health_score = @inventory_service.inventory_health_score
        @low_stock = @inventory_service.low_stock_alerts(7)
        @reorder_points = @inventory_service.calculate_reorder_points(14, 7)
        @stock_valuation = @inventory_service.stock_valuation
        @movement_summary = @inventory_service.stock_movement_summary(period_days)
      end

      def low_stock
        threshold = params[:threshold]&.to_i || 7
        @low_stock_items = @inventory_service.low_stock_alerts(threshold)

        respond_to do |format|
          format.json { render json: @low_stock_items }
          format.html
        end
      end

      def dead_stock
        no_sale_days = params[:days]&.to_i || 90
        min_value = params[:min_value]&.to_f || 100

        @dead_stock_items = @inventory_service.dead_stock_report(no_sale_days, min_value)

        respond_to do |format|
          format.json { render json: @dead_stock_items }
          format.html
        end
      end

      def turnover
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 90.days

        @turnover_data = []
        business.products.limit(50).each do |product|
          turnover_rate = @inventory_service.stock_turnover_rate(product, period)
          @turnover_data << {
            product_id: product.id,
            product_name: product.name,
            turnover_rate: turnover_rate
          }
        end

        @turnover_data.sort_by! { |d| -d[:turnover_rate] }

        respond_to do |format|
          format.json { render json: @turnover_data }
          format.html
        end
      end

      def profitability
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @profitability_data = @inventory_service.product_profitability_analysis(period)

        respond_to do |format|
          format.json { render json: @profitability_data }
          format.html
        end
      end

      def reorder_recommendations
        lead_time = params[:lead_time]&.to_i || 14
        safety_stock = params[:safety_stock]&.to_i || 7

        @recommendations = @inventory_service.calculate_reorder_points(lead_time, safety_stock)

        respond_to do |format|
          format.json { render json: @recommendations }
          format.html
        end
      end

      def valuation
        @valuation_data = @inventory_service.stock_valuation

        respond_to do |format|
          format.json { render json: @valuation_data }
          format.html
        end
      end

      def movements
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @movement_data = @inventory_service.stock_movement_summary(period)

        respond_to do |format|
          format.json { render json: @movement_data }
          format.html
        end
      end

      def health_score
        @score_data = @inventory_service.inventory_health_score

        respond_to do |format|
          format.json { render json: @score_data }
          format.html
        end
      end

      def export
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days

        csv_data = CSV.generate do |csv|
          csv << ['Inventory Analytics Export']
          csv << []

          # Health Score
          health = @inventory_service.inventory_health_score
          csv << ['Inventory Health Score', health[:score]]
          csv << ['Grade', health[:grade]]
          csv << []

          # Low Stock Alerts
          csv << ['Low Stock Alerts']
          csv << ['Product', 'Variant', 'Current Stock', 'Days Remaining', 'Reorder Qty', 'Status']
          @inventory_service.low_stock_alerts(7).each do |item|
            csv << [
              item[:product_name],
              item[:variant_name],
              item[:current_stock],
              item[:days_remaining],
              item[:recommended_reorder],
              item[:status]
            ]
          end
          csv << []

          # Dead Stock
          csv << ['Dead Stock Report']
          csv << ['Product', 'Last Sale', 'Days Since Sale', 'Stock Value', 'Action']
          @inventory_service.dead_stock_report(90, 100).each do |item|
            csv << [
              item[:product_name],
              item[:last_sale_date]&.strftime('%Y-%m-%d'),
              item[:days_since_sale],
              item[:stock_value],
              item[:recommended_action]
            ]
          end
          csv << []

          # Stock Valuation
          valuation = @inventory_service.stock_valuation
          csv << ['Stock Valuation']
          csv << ['Total Stock Value', valuation[:total_stock_value]]
          csv << ['Product Count', valuation[:product_count]]
        end

        send_data csv_data,
                  filename: "inventory-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_inventory_service
        @inventory_service = ::Analytics::InventoryIntelligenceService.new(business)
      end

      def business
        current_business
      end

      def period_to_days(period)
        case period
        when :today then 1.day
        when :last_7_days then 7.days
        when :last_30_days then 30.days
        when :last_90_days then 90.days
        else 30.days
        end
      end
    end
  end
end
