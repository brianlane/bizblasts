# frozen_string_literal: true

module Analytics
  # Service for inventory analytics and stock intelligence
  class InventoryIntelligenceService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Low stock alerts based on days of stock remaining
    def low_stock_alerts(threshold_days = 7)
      products_with_variants = business.products.includes(:product_variants)

      alerts = []

      products_with_variants.each do |product|
        product.product_variants.each do |variant|
          next if variant.stock_quantity.nil? || variant.stock_quantity <= 0

          days_remaining = calculate_days_of_stock_remaining(variant)

          if days_remaining && days_remaining < threshold_days
            alerts << {
              product_id: product.id,
              product_name: product.name,
              variant_id: variant.id,
              variant_name: variant.name,
              current_stock: variant.stock_quantity,
              days_remaining: days_remaining.round(1),
              recommended_reorder: calculate_reorder_quantity(variant),
              status: days_remaining <= 3 ? 'critical' : 'warning'
            }
          end
        end
      end

      alerts.sort_by { |a| a[:days_remaining] }
    end

    # Stock turnover rate calculation (units sold / average inventory)
    def stock_turnover_rate(product_or_variant, period = 90.days)
      if product_or_variant.is_a?(Product)
        calculate_product_turnover(product_or_variant, period)
      else
        calculate_variant_turnover(product_or_variant, period)
      end
    end

    # Dead stock identification (no sales in X days)
    def dead_stock_report(no_sale_days = 90, min_stock_value = 100)
      products = business.products.includes(:product_variants)
      dead_stock = []

      products.each do |product|
        last_sale = get_last_sale_date(product)

        if last_sale.nil? || last_sale < no_sale_days.days.ago
          stock_value = calculate_stock_value(product)

          if stock_value >= min_stock_value
            dead_stock << {
              product_id: product.id,
              product_name: product.name,
              last_sale_date: last_sale,
              days_since_sale: last_sale ? ((Time.current - last_sale) / 1.day).to_i : nil,
              current_stock: product.total_stock_quantity,
              stock_value: stock_value.round(2),
              recommended_action: recommend_dead_stock_action(last_sale, stock_value)
            }
          end
        end
      end

      dead_stock.sort_by { |s| -s[:stock_value] }
    end

    # Reorder point calculation based on lead time and sales velocity
    def calculate_reorder_points(lead_time_days = 14, safety_stock_days = 7)
      products_with_variants = business.products.includes(:product_variants)
      reorder_recommendations = []

      products_with_variants.each do |product|
        product.product_variants.each do |variant|
          next if variant.stock_quantity.nil?

          daily_sales_rate = calculate_daily_sales_rate(variant, 30.days)
          reorder_point = (daily_sales_rate * (lead_time_days + safety_stock_days)).ceil

          if variant.stock_quantity <= reorder_point
            reorder_recommendations << {
              product_id: product.id,
              product_name: product.name,
              variant_id: variant.id,
              variant_name: variant.name,
              current_stock: variant.stock_quantity,
              reorder_point: reorder_point,
              recommended_order_quantity: calculate_economic_order_quantity(variant),
              daily_sales_rate: daily_sales_rate.round(2),
              status: variant.stock_quantity <= (reorder_point * 0.5) ? 'urgent' : 'due'
            }
          end
        end
      end

      reorder_recommendations.sort_by { |r| r[:status] == 'urgent' ? 0 : 1 }
    end

    # Stock valuation (total value of inventory at cost)
    def stock_valuation
      total_value = 0
      breakdown = []

      business.products.includes(:product_variants).each do |product|
        product_value = 0

        product.product_variants.each do |variant|
          next unless variant.stock_quantity && variant.cost_price

          variant_value = variant.stock_quantity * variant.cost_price
          product_value += variant_value
        end

        if product_value > 0
          breakdown << {
            product_id: product.id,
            product_name: product.name,
            stock_value: product_value.round(2),
            stock_quantity: product.total_stock_quantity
          }
          total_value += product_value
        end
      end

      {
        total_stock_value: total_value.round(2),
        product_count: breakdown.count,
        breakdown: breakdown.sort_by { |b| -b[:stock_value] }
      }
    end

    # Product profitability analysis (requires cost tracking)
    def product_profitability_analysis(period = 30.days)
      products_with_cost = business.products.where.not(cost_price: nil)
      profitability_data = []

      products_with_cost.each do |product|
        # Calculate revenue from orders through product variants
        orders = business.orders
                        .joins(line_items: :product_variant)
                        .where(created_at: period.ago..Time.current)
                        .where(product_variants: { product_id: product.id })

        total_quantity = orders.joins(:line_items)
                              .where(line_items: { product_variant_id: product.product_variants.select(:id) })
                              .sum('line_items.quantity')
        next if total_quantity.zero?

        total_revenue = orders.joins(:line_items)
                             .where(line_items: { product_variant_id: product.product_variants.select(:id) })
                             .sum('line_items.price * line_items.quantity').to_f
        total_cost = product.cost_price.to_f * total_quantity
        gross_profit = total_revenue - total_cost
        margin_percentage = (gross_profit / total_revenue * 100).round(2)

        profitability_data << {
          product_id: product.id,
          product_name: product.name,
          units_sold: total_quantity,
          revenue: total_revenue.round(2),
          cost: total_cost.round(2),
          gross_profit: gross_profit.round(2),
          margin_percentage: margin_percentage,
          profit_per_unit: (gross_profit / total_quantity).round(2)
        }
      end

      profitability_data.sort_by { |p| -p[:gross_profit] }
    end

    # Stock movement tracking
    def stock_movement_summary(period = 30.days)
      movements = business.stock_movements.where(created_at: period.ago..Time.current)

      {
        total_movements: movements.count,
        stock_in: movements.inbound.sum(:quantity),
        stock_out: movements.outbound.sum(:quantity),
        adjustments: movements.where(movement_type: 'adjustment').sum(:quantity),
        by_type: movements.group(:movement_type).count,
        recent_movements: movements.order(created_at: :desc).limit(20).map do |movement|
          {
            date: movement.created_at,
            product_name: movement.product&.name,
            movement_type: movement.movement_type,
            quantity: movement.quantity,
            notes: movement.notes
          }
        end
      }
    end

    # Inventory health score (0-100)
    def inventory_health_score
      score = 100
      issues = []

      # Check 1: Low stock items (deduct 20 points)
      low_stock_count = low_stock_alerts(7).count
      if low_stock_count > 0
        score -= [20, low_stock_count * 5].min
        issues << "#{low_stock_count} items with low stock"
      end

      # Check 2: Dead stock (deduct 25 points)
      dead_stock_value = dead_stock_report(90, 100).sum { |s| s[:stock_value] }
      if dead_stock_value > 0
        score -= [25, (dead_stock_value / 1000 * 5).to_i].min
        issues << "#{dead_stock_value.round} in dead stock"
      end

      # Check 3: Stock turnover (deduct 20 points for slow-moving)
      products = business.products.limit(10) # Sample
      slow_turnover_count = products.count { |p| stock_turnover_rate(p, 90.days) < 1 }
      if slow_turnover_count > 3
        score -= 20
        issues << "#{slow_turnover_count} slow-moving products"
      end

      # Check 4: Stock accuracy (deduct 15 points if many adjustments)
      recent_adjustments = business.stock_movements
                                   .where(created_at: 30.days.ago..Time.current, movement_type: 'adjustment')
                                   .count
      if recent_adjustments > 10
        score -= 15
        issues << "#{recent_adjustments} stock adjustments in last 30 days"
      end

      {
        score: [score, 0].max,
        grade: score_to_grade(score),
        issues: issues,
        recommendations: generate_health_recommendations(score, issues)
      }
    end

    private

    def calculate_days_of_stock_remaining(variant)
      return nil unless variant.stock_quantity && variant.stock_quantity > 0

      daily_sales = calculate_daily_sales_rate(variant, 30.days)
      return Float::INFINITY if daily_sales.zero?

      variant.stock_quantity / daily_sales
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

    def calculate_reorder_quantity(variant)
      # Economic Order Quantity (simplified)
      daily_sales = calculate_daily_sales_rate(variant, 30.days)
      (daily_sales * 30).ceil # Order for 30 days
    end

    def calculate_economic_order_quantity(variant)
      # Simplified EOQ: 30 days of average sales
      daily_sales = calculate_daily_sales_rate(variant, 30.days)
      (daily_sales * 30).ceil
    end

    def calculate_product_turnover(product, period)
      # Total units sold / average inventory
      units_sold = business.orders
                          .joins(line_items: :product_variant)
                          .where(created_at: period.ago..Time.current)
                          .where(product_variants: { product_id: product.id })
                          .sum('line_items.quantity').to_f

      current_stock = product.total_stock_quantity.to_f

      # Estimate average inventory (current + sold / 2)
      avg_inventory = (current_stock + units_sold) / 2.0
      return 0 if avg_inventory.zero?

      (units_sold / avg_inventory).round(2)
    end

    def calculate_variant_turnover(variant, period)
      units_sold = business.orders
                          .joins(:line_items)
                          .where(created_at: period.ago..Time.current)
                          .where(line_items: { product_variant_id: variant.id })
                          .sum('line_items.quantity').to_f

      current_stock = variant.stock_quantity.to_f

      avg_inventory = (current_stock + units_sold) / 2.0
      return 0 if avg_inventory.zero?

      (units_sold / avg_inventory).round(2)
    end

    def get_last_sale_date(product)
      business.orders
              .joins(line_items: :product_variant)
              .where(product_variants: { product_id: product.id })
              .maximum('orders.created_at')
    end

    def calculate_stock_value(product)
      total_value = 0

      product.product_variants.each do |variant|
        next unless variant.stock_quantity && variant.cost_price

        total_value += variant.stock_quantity * variant.cost_price
      end

      total_value
    end

    def recommend_dead_stock_action(last_sale, stock_value)
      if last_sale.nil?
        'Review - Never sold'
      elsif last_sale < 180.days.ago
        'Discount/Clearance'
      elsif last_sale < 90.days.ago
        'Promotion'
      else
        'Monitor'
      end
    end

    def score_to_grade(score)
      case score
      when 90..100 then 'A'
      when 80..89 then 'B'
      when 70..79 then 'C'
      when 60..69 then 'D'
      else 'F'
      end
    end

    def generate_health_recommendations(score, issues)
      recommendations = []

      if issues.any? { |i| i.include?('low stock') }
        recommendations << 'Set up automatic reorder points to prevent stockouts'
      end

      if issues.any? { |i| i.include?('dead stock') }
        recommendations << 'Run clearance promotions for slow-moving inventory'
      end

      if issues.any? { |i| i.include?('slow-moving') }
        recommendations << 'Analyze product demand and adjust purchasing strategy'
      end

      if issues.any? { |i| i.include?('adjustments') }
        recommendations << 'Review stock counting procedures to improve accuracy'
      end

      recommendations << 'Overall inventory management is healthy' if score >= 90

      recommendations
    end
  end
end
