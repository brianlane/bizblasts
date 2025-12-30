# frozen_string_literal: true

require 'csv'

module BusinessManager
  module Analytics
    # Controller for predictive analytics and intelligent forecasting
    class PredictiveController < BusinessManager::BaseController
      before_action :set_predictive_service

      def index
        @revenue_prediction = @predictive_service.predict_revenue(30)
        @anomalies = @predictive_service.detect_anomalies(:bookings, 30.days)
        @restock_predictions = @predictive_service.predict_restock_needs(30).first(10)
        @scheduling_optimization = @predictive_service.optimize_staff_scheduling(Date.current)
      end

      def demand_forecast
        period = params[:period]&.to_i || 30

        # Overall demand forecast
        all_services = business.services.active
        total_predicted = 0
        total_revenue_predicted = 0

        @demand_by_service = all_services.map do |service|
          forecast_data = @predictive_service.forecast_service_demand(service.id, period)
          total_bookings = forecast_data[:forecast].sum { |f| f[:forecasted_bookings] }
          total_predicted += total_bookings
          total_revenue_predicted += total_bookings * service.price

          {
            service_name: service.name,
            category: 'Service',
            historical_avg: forecast_data[:historical_avg],
            predicted: total_bookings,
            predicted_revenue: total_bookings * service.price,
            change_percent: forecast_data[:historical_avg] > 0 ? ((total_bookings - (forecast_data[:historical_avg] * period)) / (forecast_data[:historical_avg] * period) * 100).round(1) : 0,
            confidence: (forecast_data[:forecast].first&.dig(:confidence_level) || 75).to_f,
            trend: forecast_data[:trend_direction]
          }
        end

        # Get historical data for comparison
        historical_bookings = business.bookings.where(created_at: period.days.ago..Time.current).count

        @demand_forecast = {
          total_bookings_predicted: total_predicted,
          total_revenue_predicted: total_revenue_predicted,
          confidence_level: @demand_by_service.any? ? @demand_by_service.sum { |s| s[:confidence] } / @demand_by_service.count : 75,
          peak_day: (Date.current + (period / 2).days).strftime('%A'),
          peak_bookings: (total_predicted * 1.2 / period).round,
          change_from_previous: historical_bookings > 0 ? ((total_predicted - historical_bookings).to_f / historical_bookings * 100).round(1) : 0,
          historical_daily_avg: historical_bookings.to_f / period,
          max_daily: (total_predicted * 1.5 / period).round
        }

        # Daily forecast
        @daily_forecast = (0...period).map do |day_offset|
          date = Date.current + day_offset.days
          # Use day-of-week multiplier instead of random values
          # Weekdays typically have higher demand, weekends lower
          day_multiplier = [0.7, 0.9, 1.0, 1.1, 1.2, 0.95, 0.75][date.wday]
          daily_bookings = (total_predicted.to_f / period * day_multiplier).round
          avg_revenue_per_booking = total_predicted > 0 ? (total_revenue_predicted / total_predicted) : 0

          # Calculate confidence based on historical data volume
          historical_data_points = @demand_by_service.sum { |s| s[:historical_avg] > 0 ? 1 : 0 }
          base_confidence = [50 + (historical_data_points * 5), 90].min

          {
            date: date,
            predicted_bookings: daily_bookings,
            predicted_revenue: daily_bookings * avg_revenue_per_booking,
            confidence: base_confidence
          }
        end

        # Recommendations
        @demand_forecast[:recommendations] = [
          {
            priority: @demand_forecast[:change_from_previous] < -10 ? 'high' : 'medium',
            title: 'Increase Marketing During Low Demand Periods',
            description: 'Focus promotional efforts on services showing declining demand trends.'
          },
          {
            priority: 'medium',
            title: 'Optimize Staff Scheduling',
            description: "Ensure adequate staffing on #{@demand_forecast[:peak_day]} to handle peak demand."
          }
        ]

        respond_to do |format|
          format.json { render json: @demand_forecast }
          format.html
        end
      end

      def pricing_recommendations
        all_services = business.services.active

        @pricing_recommendations = all_services.map do |service|
          pricing_data = @predictive_service.optimal_pricing_recommendations(service.id)
          demand_level = service.bookings.where(created_at: 30.days.ago..Time.current).count > 20 ? 'high' : service.bookings.where(created_at: 30.days.ago..Time.current).count > 10 ? 'medium' : 'low'

          # Calculate confidence based on booking volume (more bookings = higher confidence)
          booking_count = pricing_data[:current_monthly_bookings].to_i
          confidence_level = if booking_count >= 30
                              85 # High confidence with sufficient data
                            elsif booking_count >= 15
                              75 # Medium confidence
                            elsif booking_count >= 5
                              65 # Low confidence
                            else
                              50 # Very low confidence with minimal data
                            end

          {
            service_name: service.name,
            current_price: service.price,
            recommended_price: pricing_data[:optimal_price],
            price_range_min: (pricing_data[:optimal_price] * 0.9).round(2),
            price_range_max: (pricing_data[:optimal_price] * 1.1).round(2),
            demand_level: demand_level,
            primary_reason: pricing_data[:revenue_increase_potential] > 0 ? 'Increase revenue potential' : 'Optimize for market positioning',
            factors: ['Historical demand', 'Market analysis', 'Booking trends'],
            revenue_impact: (pricing_data[:optimal_price] - service.price) * pricing_data[:optimal_monthly_bookings],
            confidence_level: confidence_level,
            booking_count: booking_count
          }
        end

        # Summary
        total_current = all_services.sum(&:price)
        total_recommended = @pricing_recommendations.sum { |r| r[:recommended_price] }

        @pricing_summary = {
          current_avg_price: all_services.any? ? total_current / all_services.count : 0,
          recommended_avg_price: all_services.any? ? total_recommended / all_services.count : 0,
          revenue_impact: @pricing_recommendations.sum { |r| r[:revenue_impact] },
          services_to_optimize: @pricing_recommendations.count { |r| (r[:recommended_price] - r[:current_price]).abs > 5 }
        }

        @premium_candidates = @pricing_recommendations.select { |r| r[:demand_level] == 'high' && r[:recommended_price] > r[:current_price] }.first(3).map do |r|
          increase_potential = r[:current_price] > 0 ? ((r[:recommended_price] - r[:current_price]) / r[:current_price] * 100).round(1) : 0
          { name: r[:service_name], increase_potential: increase_potential }
        end

        @promotional_candidates = @pricing_recommendations.select { |r| r[:demand_level] == 'low' }.first(3).map do |r|
          { name: r[:service_name], discount_suggested: 15 }
        end

        @market_comparison = all_services.first(5).map do |service|
          # Use optimal price as market average estimate (from pricing analysis)
          pricing_rec = @pricing_recommendations.find { |r| r[:service_name] == service.name }
          market_avg = pricing_rec ? pricing_rec[:recommended_price] : service.price

          {
            service_name: service.name,
            your_price: service.price,
            market_min: (market_avg * 0.8).round(2),
            market_max: (market_avg * 1.2).round(2),
            market_position_percent: market_avg > 0 ? ((service.price - market_avg * 0.8) / (market_avg * 0.4) * 100).round : 50,
            market_spread_percent: 40, # Typical market spread is 40% (±20%)
            your_position_percent: market_avg > 0 ? ((service.price - market_avg * 0.8) / (market_avg * 0.4) * 100).round : 50,
            position: service.price > market_avg * 1.1 ? 'above' : service.price < market_avg * 0.9 ? 'below' : 'competitive'
          }
        end

        @pricing_insights = [
          { title: 'High-Demand Services', description: 'Premium pricing opportunity for services with consistently high booking rates.' },
          { title: 'Competitive Positioning', description: 'Your prices are generally aligned with market averages for similar services.' }
        ]

        respond_to do |format|
          format.json { render json: @pricing_recommendations }
          format.html
        end
      end

      def apply_pricing
        service_name = params[:service_name]
        recommended_price = params[:recommended_price].to_f

        service = business.services.find_by(name: service_name)

        if service.nil?
          redirect_to pricing_recommendations_business_manager_analytics_predictive_index_path,
                      alert: "Service '#{service_name}' not found."
          return
        end

        old_price = service.price
        service.price = recommended_price

        if service.save
          redirect_to pricing_recommendations_business_manager_analytics_predictive_index_path,
                      notice: "Successfully updated '#{service.name}' price from #{number_to_currency(old_price)} to #{number_to_currency(recommended_price)}."
        else
          redirect_to pricing_recommendations_business_manager_analytics_predictive_index_path,
                      alert: "Failed to update price for '#{service.name}': #{service.errors.full_messages.join(', ')}"
        end
      end

      def apply_all_pricing
        all_services = business.services.active
        updated_count = 0
        failed_services = []

        all_services.each do |service|
          pricing_data = @predictive_service.optimal_pricing_recommendations(service.id)
          recommended_price = pricing_data[:optimal_price]

          # Only update if the recommended price is significantly different (more than $5 difference)
          if (recommended_price - service.price).abs > 5
            old_price = service.price
            service.price = recommended_price

            if service.save
              updated_count += 1
            else
              failed_services << service.name
            end
          end
        end

        if failed_services.any?
          redirect_to pricing_recommendations_business_manager_analytics_predictive_index_path,
                      alert: "Updated #{updated_count} services. Failed to update: #{failed_services.join(', ')}"
        else
          redirect_to pricing_recommendations_business_manager_analytics_predictive_index_path,
                      notice: "Successfully updated pricing for #{updated_count} #{'service'.pluralize(updated_count)}."
        end
      end

      def anomalies
        metric_type = params[:metric]&.to_sym || :bookings
        period = params[:period]&.to_i&.days || 30.days

        anomalies_data = @predictive_service.detect_anomalies(metric_type, period)

        # Format anomalies for the view
        @anomalies = anomalies_data.map do |anomaly|
          # Parse expected_range correctly (handles negative values)
          # Format is "min - max" with spaces around the dash
          range_parts = anomaly[:expected_range].split(' - ')
          expected_min = range_parts.first.to_f
          expected_max = range_parts.last.to_f

          {
            title: "Unusual #{anomaly[:metric].to_s.titleize} Activity",
            description: "Detected #{anomaly[:direction]} trend outside normal range",
            category: determine_anomaly_category(anomaly[:metric]),
            severity: anomaly[:severity],
            current_value: anomaly[:value],
            expected_min: expected_min,
            expected_max: expected_max,
            deviation_percent: anomaly[:deviation_percentage],
            metric_type: 'currency',
            detected_days_ago: ((Time.current - anomaly[:date].to_time) / 1.day).to_i,
            possible_causes: ['Seasonal variation', 'Market changes', 'Operational issues'],
            recommended_actions: ['Monitor closely', 'Investigate root cause', 'Adjust forecasts']
          }
        end

        @anomaly_summary = {
          critical: @anomalies.count { |a| a[:severity] == 'critical' },
          high: @anomalies.count { |a| a[:severity] == 'high' },
          medium: @anomalies.count { |a| a[:severity] == 'medium' },
          low: @anomalies.count { |a| a[:severity] == 'low' }
        }

        @category_counts = {
          revenue: @anomalies.count { |a| a[:category] == 'revenue' },
          bookings: @anomalies.count { |a| a[:category] == 'bookings' },
          customers: @anomalies.count { |a| a[:category] == 'customers' },
          operations: @anomalies.count { |a| a[:category] == 'operations' }
        }

        respond_to do |format|
          format.json { render json: @anomalies }
          format.html
        end
      end

      def save_anomaly_settings
        # Store settings in session for now (future: persist to business settings or user preferences)
        session[:anomaly_settings] = {
          detection_sensitivity: params[:detection_sensitivity],
          deviation_threshold: params[:deviation_threshold],
          monitoring_period: params[:monitoring_period],
          email_notifications: params[:email_notifications]
        }

        redirect_to anomalies_business_manager_analytics_predictive_index_path,
                    notice: 'Anomaly detection settings saved successfully.'
      end

      def next_purchase
        customer_id = params[:customer_id]

        if customer_id
          customer = business.tenant_customers.find(customer_id)
          @prediction = @predictive_service.predict_next_purchase(customer)
        end

        @customers = business.tenant_customers.order(:last_name).limit(100)

        respond_to do |format|
          format.json { render json: @prediction }
          format.html
        end
      end

      def staff_scheduling
        date = params[:date]&.to_date || Date.current
        scheduling_data = @predictive_service.optimize_staff_scheduling(date)

        # Calculate weekly demand heatmap (7 days x 13 hours: 8am-8pm)
        @demand_heatmap = Array.new(7) { Array.new(13) { 0 } }
        bookings_90_days = business.bookings.where(start_time: 90.days.ago..Time.current)

        bookings_90_days.each do |booking|
          day_of_week = booking.start_time.wday
          hour = booking.start_time.hour
          if hour >= 8 && hour <= 20
            hour_index = hour - 8
            @demand_heatmap[day_of_week][hour_index] += 1
          end
        end

        # Normalize to 0-100 scale
        max_bookings = @demand_heatmap.flatten.max || 1
        @demand_heatmap = @demand_heatmap.map do |day|
          day.map { |count| (count.to_f / max_bookings * 100).round }
        end

        # Staff utilization by member
        all_staff = business.staff_members.active
        @staff_utilization = all_staff.map do |staff|
          week_bookings = staff.bookings.where(start_time: date.beginning_of_week..date.end_of_week)
          total_hours = week_bookings.sum { |b| (b.duration_minutes || 60) / 60.0 }
          available_hours = 40 # Assume 40 hour work week
          utilization = available_hours > 0 ? (total_hours / available_hours * 100).round(1) : 0

          # Generate initials from name
          name_parts = staff.full_name.split(' ')
          initials = name_parts.map { |part| part[0]&.upcase }.join

          # Determine recommendation based on utilization
          recommendation = if utilization < 40
                             'Consider assigning more shifts or cross-training'
                           elsif utilization > 90
                             'At risk of burnout - consider redistributing workload'
                           else
                             nil
                           end

          {
            name: staff.full_name,
            initials: initials,
            role: staff.position || 'Staff Member',
            booked_hours: total_hours.round(1),
            hours_scheduled: total_hours.round(1),
            available_hours: available_hours,
            utilization_percent: utilization,
            bookings_count: week_bookings.count,
            recommendation: recommendation
          }
        end

        # Scheduling summary - calculate optimal staff count and potential savings
        underutilized = @staff_utilization.count { |s| s[:utilization_percent] < 60 }
        overutilized = @staff_utilization.count { |s| s[:utilization_percent] > 90 }
        optimal = @staff_utilization.count { |s| s[:utilization_percent].between?(60, 90) }

        # Calculate potential savings from optimizing underutilized staff
        hourly_rate = 25 # Assume average hourly rate
        potential_savings = underutilized * 10 * hourly_rate * 4 # 10 hours/week * $25 * 4 weeks

        @scheduling_summary = {
          total_staff: all_staff.count,
          optimal_staff_count: [all_staff.count - underutilized, 1].max,
          overstaffed_shifts: underutilized,
          understaffed_shifts: overutilized,
          potential_savings: potential_savings,
          avg_utilization: @staff_utilization.any? ? (@staff_utilization.sum { |s| s[:utilization_percent] } / @staff_utilization.count).round(1) : 0,
          underutilized_staff: underutilized,
          overutilized_staff: overutilized,
          optimal_staff: optimal
        }

        # Peak hours coverage analysis
        @peak_hours_coverage = []
        day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
        peak_hours = [10, 11, 14, 15, 16] # 10am-11am, 2pm-4pm

        peak_hours.each do |hour|
          # Count staff with bookings during this hour as available
          coverage = all_staff.count do |staff|
            staff.bookings.where(
              'start_time >= ? AND start_time < ?',
              date.beginning_of_day + hour.hours,
              date.beginning_of_day + (hour + 1).hours
            ).exists?
          end
          # If no bookings data, assume all staff are potentially available
          coverage = all_staff.count if coverage.zero?

          hour_index = hour - 8
          demand = @demand_heatmap.dig(date.wday, hour_index) || 0
          staff_needed = [(demand / 20.0).ceil, 1].max # 1 staff per 20% demand

          @peak_hours_coverage << {
            day: day_names[date.wday],
            time_range: "#{hour}:00 - #{hour + 1}:00",
            expected_bookings: (demand / 10.0).round,
            staff_scheduled: coverage,
            staff_needed: staff_needed,
            staff_difference: coverage - staff_needed,
            coverage_adequate: coverage >= staff_needed,
            hour: "#{hour}:00",
            staff_available: coverage,
            demand_level: demand,
            adequate: coverage >= 3
          }
        end

        # Schedule recommendations with all required fields
        @schedule_recommendations = []

        if @scheduling_summary[:underutilized_staff] > 0
          @schedule_recommendations << {
            priority: 'medium',
            title: 'Reduce Underutilized Staff Hours',
            description: "#{@scheduling_summary[:underutilized_staff]} staff members are underutilized (<60%). Consider reducing scheduled hours or cross-training for other tasks.",
            shift_time: 'Various shifts',
            current_staff: all_staff.count,
            recommended_staff: @scheduling_summary[:optimal_staff_count],
            impact: potential_savings,
            rationale: 'Based on historical booking patterns and current utilization rates'
          }
        end

        if @scheduling_summary[:overutilized_staff] > 0
          @schedule_recommendations << {
            priority: 'high',
            title: 'Address Overutilization',
            description: "#{@scheduling_summary[:overutilized_staff]} staff members are overutilized (>90%). Consider hiring additional staff or redistributing workload.",
            shift_time: 'Peak hours',
            current_staff: all_staff.count,
            recommended_staff: all_staff.count + 1,
            impact: -2000, # Cost to add staff
            rationale: 'High utilization leads to burnout and reduced service quality'
          }
        end

        insufficient_coverage = @peak_hours_coverage.count { |p| !p[:coverage_adequate] }
        if insufficient_coverage > 0
          @schedule_recommendations << {
            priority: 'high',
            title: 'Increase Peak Hour Coverage',
            description: "#{insufficient_coverage} peak hours have insufficient staff coverage. Ensure at least 3 staff members during high-demand periods.",
            shift_time: '10:00 AM - 4:00 PM',
            current_staff: @peak_hours_coverage.map { |p| p[:staff_scheduled] }.min || 0,
            recommended_staff: 3,
            impact: 500, # Potential revenue from better coverage
            rationale: 'Peak hours generate highest revenue - adequate staffing is critical'
          }
        end

        # Add a default recommendation if none exist
        if @schedule_recommendations.empty?
          @schedule_recommendations << {
            priority: 'low',
            title: 'Maintain Current Schedule',
            description: 'Staff scheduling is well optimized. Continue monitoring utilization rates.',
            shift_time: 'All shifts',
            current_staff: all_staff.count,
            recommended_staff: all_staff.count,
            impact: 0,
            rationale: 'Current staffing levels match demand patterns'
          }
        end

        # Scheduling insights with type field
        total_staff_safe = [@scheduling_summary[:total_staff], 1].max
        @scheduling_insights = [
          {
            type: 'info',
            title: 'Optimal Staffing Levels',
            description: "#{@scheduling_summary[:optimal_staff]} staff members (#{(@scheduling_summary[:optimal_staff].to_f / total_staff_safe * 100).round}%) are at optimal utilization (60-90%)."
          },
          {
            type: 'opportunity',
            title: 'Peak Demand Days',
            description: 'Weekdays show highest demand. Ensure adequate coverage Monday-Friday 10am-4pm.'
          },
          {
            type: @scheduling_summary[:overutilized_staff] > 0 ? 'warning' : 'info',
            title: 'Staff Workload Balance',
            description: @scheduling_summary[:overutilized_staff] > 0 ? 'Some staff members are overworked. Review workload distribution.' : 'Staff workload is well balanced across the team.'
          },
          {
            type: 'opportunity',
            title: 'Scheduling Efficiency',
            description: "Average staff utilization is #{@scheduling_summary[:avg_utilization]}%. Target range is 60-90%."
          }
        ]

        respond_to do |format|
          format.json { render json: scheduling_data }
          format.html
        end
      end

      def restock_predictions
        days_ahead = params[:days]&.to_i || 30
        restock_data = @predictive_service.predict_restock_needs(days_ahead)

        # Separate critical from regular restocks
        @critical_restocks = restock_data.select { |r| r[:urgency] == 'critical' && r[:days_until_stockout] <= 3 }
        @restock_recommendations = restock_data.reject { |r| r[:urgency] == 'critical' && r[:days_until_stockout] <= 3 }

        # Restock summary
        all_variants = ProductVariant.joins(:product).where(products: { business_id: business.id }).includes(:product)

        @restock_summary = {
          total_products_tracked: restock_data.count,
          critical_count: @critical_restocks.count,
          warning_count: @restock_recommendations.count { |r| r[:days_until_stockout] <= 7 },
          healthy_count: all_variants.count - restock_data.count,
          total_order_value: restock_data.sum { |r| (r[:recommended_order_quantity] || 0) * (r[:unit_cost] || 0) }
        }

        # Identify overstocked products (high stock, low sales)
        @overstocked_products = all_variants.select do |variant|
          sales_30_days = variant.line_items.where(created_at: 30.days.ago..Time.current).sum(:quantity)
          stock = variant.stock_quantity || 0
          days_of_stock = sales_30_days > 0 ? (stock.to_f / (sales_30_days / 30.0)) : Float::INFINITY

          days_of_stock > 90 && stock > 10
        end.map do |variant|
          sales_30_days = variant.line_items.where(created_at: 30.days.ago..Time.current).sum(:quantity)
          {
            product_name: variant.product.name,
            variant_name: variant.name || 'Default',
            current_stock: variant.stock_quantity,
            monthly_sales: sales_30_days,
            days_of_stock: sales_30_days > 0 ? ((variant.stock_quantity || 0).to_f / (sales_30_days / 30.0)).round : 999,
            excess_units: [variant.stock_quantity - (sales_30_days * 3), 0].max
          }
        end.first(10)

        # Seasonal demand adjustments
        @seasonal_adjustments = [
          {
            season: 'Current Season',
            adjustment_factor: 1.0,
            description: 'Standard demand patterns'
          },
          {
            season: 'Next Quarter',
            adjustment_factor: 1.15,
            description: 'Increase orders by 15% based on historical trends'
          }
        ]

        # Supplier performance (mock data for now - TODO: implement actual supplier tracking)
        @supplier_performance = business.products.includes(:product_variants)
                                       .group_by { |p| 'Default Supplier' }
                                       .map do |supplier, products|
          # Calculate reliability based on product count (more products = established relationship)
          reliability_score = [60 + (products.count * 2), 95].min

          {
            supplier_name: supplier,
            products_supplied: products.count,
            avg_lead_time: 7, # days - TODO: track actual lead times
            reliability_score: reliability_score,
            last_delivery: 14.days.ago.to_date # Default to 2 weeks ago - TODO: track actual deliveries
          }
        end.first(5)

        # Restock insights
        @restock_insights = []

        if @critical_restocks.any?
          @restock_insights << {
            priority: 'critical',
            title: 'Urgent Restocks Required',
            description: "#{@critical_restocks.count} products will stock out in 3 days or less. Place orders immediately."
          }
        end

        if @overstocked_products.any?
          @restock_insights << {
            priority: 'medium',
            title: 'Reduce Excess Inventory',
            description: "#{@overstocked_products.count} products are overstocked with 90+ days of inventory. Consider promotions to move excess stock."
          }
        end

        @restock_insights << {
          priority: 'low',
          title: 'Optimize Order Frequency',
          description: 'Review ordering patterns to reduce carrying costs while maintaining adequate stock levels.'
        }

        respond_to do |format|
          format.json { render json: restock_data }
          format.html
        end
      end

      def export_restock_predictions
        days_ahead = params[:days]&.to_i || 30
        restock_data = @predictive_service.predict_restock_needs(days_ahead)

        # Generate CSV
        csv_data = CSV.generate(headers: true) do |csv|
          # Header row
          csv << [
            'Product',
            'SKU',
            'Current Stock',
            'Reorder Point',
            'Days Until Stockout',
            'Recommended Qty',
            'Unit Cost',
            'Order Value',
            'Lead Time (days)',
            'Order By Date',
            'Urgency'
          ]

          # Data rows
          restock_data.each do |product|
            csv << [
              product[:name],
              product[:sku],
              product[:current_stock],
              product[:reorder_point],
              product[:days_until_stockout],
              product[:recommended_order_quantity],
              number_to_currency(product[:unit_cost] || 0),
              number_to_currency((product[:recommended_order_quantity] || 0) * (product[:unit_cost] || 0)),
              product[:lead_time_days],
              product[:order_by_date]&.strftime('%Y-%m-%d'),
              product[:urgency]
            ]
          end
        end

        send_data csv_data,
                  filename: "restock_predictions_#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      def create_purchase_orders
        days_ahead = params[:days]&.to_i || 30
        restock_data = @predictive_service.predict_restock_needs(days_ahead)

        # Filter to only items that need restocking (days until stockout <= 30)
        items_to_order = restock_data.select { |r| r[:days_until_stockout] <= days_ahead }

        if items_to_order.empty?
          redirect_to restock_predictions_business_manager_analytics_predictive_index_path,
                      alert: 'No products currently need restocking.'
          return
        end

        # TODO: Create actual purchase orders once PurchaseOrder model is implemented
        # For now, we'll just show a summary and redirect with a success message

        total_items = items_to_order.count
        total_value = items_to_order.sum { |r| (r[:recommended_order_quantity] || 0) * (r[:unit_cost] || 0) }
        critical_items = items_to_order.count { |r| r[:urgency] == 'critical' }

        redirect_to restock_predictions_business_manager_analytics_predictive_index_path,
                    notice: "Purchase order summary: #{total_items} #{'item'.pluralize(total_items)} totaling #{number_to_currency(total_value)} (#{critical_items} critical). Purchase order system coming soon!"
      end

      def revenue_prediction
        days_ahead = params[:days]&.to_i || 30
        revenue_data = @predictive_service.predict_revenue(days_ahead)

        # Revenue forecast with multiple time horizons
        @revenue_forecast = {
          period_30: revenue_data[:predicted_total],
          period_60: revenue_data[:predicted_total] * 2,
          period_90: revenue_data[:predicted_total] * 3,
          period_365: revenue_data[:predicted_total] * 12,
          confidence_30: revenue_data[:confidence_level] || 85,
          confidence_60: (revenue_data[:confidence_level] || 85) - 5,
          confidence_90: (revenue_data[:confidence_level] || 85) - 10,
          confidence_365: (revenue_data[:confidence_level] || 85) - 20,
          historical_daily_avg: revenue_data[:historical_daily_avg],
          trend_direction: revenue_data[:trend_direction],
          growth_rate: revenue_data[:growth_rate] || 0
        }

        # Daily revenue forecast
        @daily_forecast = []
        # Calculate confidence based on historical data volume
        total_payments = business.payments.where(status: 'completed', created_at: 90.days.ago..Time.current).count
        base_confidence = if total_payments >= 100
                           85 # High confidence with substantial data
                         elsif total_payments >= 50
                           75 # Medium confidence
                         elsif total_payments >= 20
                           65 # Low confidence
                         else
                           50 # Very low confidence
                         end

        days_ahead.times do |day_offset|
          date = Date.current + day_offset.days
          base_revenue = revenue_data[:historical_daily_avg]
          day_factor = [0.7, 0.8, 1.0, 1.1, 1.2, 0.9, 0.6][date.wday] # Weekend adjustments
          # Reduce confidence for predictions further in the future
          days_out_confidence_penalty = [0, (day_offset / 10)].min

          @daily_forecast << {
            date: date,
            predicted_revenue: (base_revenue * day_factor).round(2),
            lower_bound: (base_revenue * day_factor * 0.85).round(2),
            upper_bound: (base_revenue * day_factor * 1.15).round(2),
            confidence: [base_confidence - days_out_confidence_penalty, 50].max
          }
        end

        # Revenue breakdown by category
        service_categories = business.services.includes(:service_category).group_by { |s| s.service_category&.name || 'Uncategorized' }
        @revenue_by_category = service_categories.map do |category, services|
          historical_revenue = services.sum do |service|
            service.bookings.where(created_at: 90.days.ago..Time.current)
                   .joins(:payments)
                   .where(payments: { status: 'completed' })
                   .sum('payments.amount')
          end

          predicted_revenue = (historical_revenue / 90.0 * days_ahead).round(2)

          # Calculate growth potential based on booking trends
          older_period_revenue = services.sum do |service|
            service.bookings.where(created_at: 180.days.ago..90.days.ago)
                   .joins(:payments)
                   .where(payments: { status: 'completed' })
                   .sum('payments.amount')
          end

          # Growth potential = how much revenue could grow if recent trend continues
          if older_period_revenue > 0
            actual_growth_rate = ((historical_revenue - older_period_revenue) / older_period_revenue * 100).round(1)
            # Clamp to realistic range (5-25%)
            growth_potential = [[actual_growth_rate, 5].max, 25].min
          else
            growth_potential = 10 # Default 10% growth potential if no historical comparison
          end

          {
            category: category,
            historical_revenue: historical_revenue,
            predicted_revenue: predicted_revenue,
            services_count: services.count,
            growth_potential: growth_potential
          }
        end.sort_by { |c| -c[:predicted_revenue] }

        # Revenue by stream (bookings vs products vs subscriptions)
        bookings_revenue = business.bookings.where(created_at: 90.days.ago..Time.current)
                                  .joins(:payments)
                                  .where(payments: { status: 'completed' })
                                  .sum('payments.amount')

        products_revenue = business.orders.where(created_at: 90.days.ago..Time.current)
                                  .joins(:payments)
                                  .where(payments: { status: 'completed' })
                                  .sum('payments.amount')

        subscriptions_revenue = business.customer_subscriptions.active
                                       .sum { |sub| sub.amount * 3 } # 3 months worth

        total_historical = bookings_revenue + products_revenue + subscriptions_revenue

        @revenue_by_stream = [
          {
            stream: 'Service Bookings',
            historical: bookings_revenue,
            predicted: (bookings_revenue / 90.0 * days_ahead).round(2),
            percentage: total_historical > 0 ? (bookings_revenue.to_f / total_historical * 100).round(1) : 0
          },
          {
            stream: 'Product Sales',
            historical: products_revenue,
            predicted: (products_revenue / 90.0 * days_ahead).round(2),
            percentage: total_historical > 0 ? (products_revenue.to_f / total_historical * 100).round(1) : 0
          },
          {
            stream: 'Subscriptions',
            historical: subscriptions_revenue,
            predicted: (subscriptions_revenue / 3.0 * (days_ahead / 30.0)).round(2),
            percentage: total_historical > 0 ? (subscriptions_revenue.to_f / total_historical * 100).round(1) : 0
          }
        ].sort_by { |s| -s[:predicted] }

        # ML Model performance metrics (simulated for now)
        @model_performance = {
          accuracy: 87.5,
          mae: revenue_data[:historical_daily_avg] * 0.12, # Mean Absolute Error
          rmse: revenue_data[:historical_daily_avg] * 0.18, # Root Mean Square Error
          precision: 85.2,
          last_trained: 7.days.ago.to_date,
          training_samples: business.payments.where(status: 'completed').count
        }

        # Risk factors affecting forecast accuracy
        @risk_factors = []

        if revenue_data[:trend_direction] == 'declining'
          @risk_factors << {
            severity: 'high',
            factor: 'Declining Revenue Trend',
            description: 'Historical data shows declining revenue pattern. Forecast assumes stabilization.',
            impact: 'May overestimate future revenue by 10-20%'
          }
        end

        if business.bookings.where(created_at: 90.days.ago..Time.current).count < 100
          @risk_factors << {
            severity: 'medium',
            factor: 'Limited Historical Data',
            description: 'Less than 100 bookings in past 90 days reduces prediction accuracy.',
            impact: 'Confidence intervals may be wider than indicated'
          }
        end

        seasonal_variance = @daily_forecast.map { |d| d[:predicted_revenue] }.then do |revenues|
          next 0 if revenues.empty?
          mean = revenues.sum / revenues.count
          next 0 if mean.zero? # Avoid division by zero when all revenues are zero
          variance = revenues.sum { |r| (r - mean) ** 2 } / revenues.count
          Math.sqrt(variance) / mean * 100
        end

        if seasonal_variance > 30
          @risk_factors << {
            severity: 'medium',
            factor: 'High Seasonal Variance',
            description: 'Revenue shows significant day-to-day variation.',
            impact: 'Individual day predictions may vary by ±30%'
          }
        end

        # Growth opportunities
        @growth_opportunities = []

        underperforming_categories = @revenue_by_category.select { |c| c[:growth_potential] > 15 }
        if underperforming_categories.any?
          @growth_opportunities << {
            opportunity: 'Service Category Optimization',
            description: "#{underperforming_categories.count} categories show 15%+ growth potential through targeted marketing.",
            potential_revenue: underperforming_categories.sum { |c| c[:predicted_revenue] * 0.15 }.round(2)
          }
        end

        if @revenue_by_stream.any? { |s| s[:percentage] < 10 }
          underutilized_stream = @revenue_by_stream.find { |s| s[:percentage] < 10 }
          @growth_opportunities << {
            opportunity: "Expand #{underutilized_stream[:stream]}",
            description: "#{underutilized_stream[:stream]} represents only #{underutilized_stream[:percentage]}% of revenue. Significant growth opportunity.",
            potential_revenue: (total_historical * 0.05).round(2)
          }
        end

        @growth_opportunities << {
          opportunity: 'Price Optimization',
          description: 'Dynamic pricing strategy could increase revenue by 5-8% without reducing demand.',
          potential_revenue: (@revenue_forecast[:period_30] * 0.065).round(2)
        }

        # Strategic recommendations
        @strategic_recommendations = []

        if revenue_data[:trend_direction] == 'growing'
          @strategic_recommendations << {
            priority: 'high',
            title: 'Capitalize on Growth Momentum',
            description: 'Revenue is trending upward. Increase marketing spend and expand high-performing service offerings.',
            expected_impact: '+12% revenue growth'
          }
        elsif revenue_data[:trend_direction] == 'declining'
          @strategic_recommendations << {
            priority: 'critical',
            title: 'Address Revenue Decline',
            description: 'Implement retention campaigns, review pricing strategy, and identify service quality issues.',
            expected_impact: 'Stabilize revenue, prevent further -5% decline'
          }
        end

        @strategic_recommendations << {
          priority: 'medium',
          title: 'Diversify Revenue Streams',
          description: 'Reduce dependency on single revenue source by expanding underutilized streams.',
          expected_impact: '+8% revenue, reduced risk'
        }

        @strategic_recommendations << {
          priority: 'medium',
          title: 'Seasonal Demand Planning',
          description: 'Prepare inventory and staffing for predicted peak periods to maximize revenue capture.',
          expected_impact: '+5% revenue during peak periods'
        }

        respond_to do |format|
          format.json { render json: revenue_data }
          format.html
        end
      end

      def export
        csv_data = CSV.generate do |csv|
          csv << ['Predictive Analytics Export']
          csv << []

          # Revenue prediction
          revenue_pred = @predictive_service.predict_revenue(30)
          csv << ['Revenue Prediction (Next 30 Days)']
          csv << ['Historical Daily Avg', revenue_pred[:historical_daily_avg]]
          csv << ['Trend Direction', revenue_pred[:trend_direction]]
          csv << ['Predicted Total (30 days)', revenue_pred[:predicted_total]]
          csv << []

          # Anomalies
          csv << ['Recent Anomalies (Last 30 Days)']
          csv << ['Date', 'Metric', 'Value', 'Expected Range', 'Severity', 'Direction']
          @predictive_service.detect_anomalies(:bookings, 30.days).each do |anomaly|
            csv << [
              anomaly[:date],
              anomaly[:metric],
              anomaly[:value],
              anomaly[:expected_range],
              anomaly[:severity],
              anomaly[:direction]
            ]
          end
          csv << []

          # Restock predictions
          csv << ['Inventory Restock Predictions']
          csv << ['Product', 'Variant', 'Current Stock', 'Daily Sales', 'Days Until Stockout', 'Urgency']
          @predictive_service.predict_restock_needs(30).each do |pred|
            csv << [
              pred[:product_name],
              pred[:variant_name],
              pred[:current_stock],
              pred[:daily_sales_rate],
              pred[:days_until_stockout],
              pred[:urgency]
            ]
          end
        end

        send_data csv_data,
                  filename: "predictive-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_predictive_service
        @predictive_service = ::Analytics::PredictiveService.new(business)
      end

      def business
        current_business
      end

      def determine_anomaly_category(metric)
        case metric.to_sym
        when :revenue, :payment_amount, :refunds
          'revenue'
        when :bookings, :appointments, :reservations
          'bookings'
        when :customers, :new_customers, :customer_count
          'customers'
        when :cancellations, :no_shows, :staff_availability
          'operations'
        else
          'operations'
        end
      end
    end
  end
end
