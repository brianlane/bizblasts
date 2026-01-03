# frozen_string_literal: true

module Analytics
  # Service for analyzing product performance and sales metrics
  class ProductAnalyticsService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Get comprehensive product metrics for a period
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Product metrics
    def metrics(start_date: 30.days.ago, end_date: Time.current)
      orders = business.orders.where(created_at: start_date..end_date)
      product_views = product_page_views(start_date, end_date)
      
      {
        total_orders: orders.count,
        completed_orders: orders.where(status: [:completed, :delivered]).count,
        total_revenue: calculate_total_revenue(orders),
        average_order_value: calculate_average_order_value(orders),
        total_items_sold: calculate_total_items_sold(orders),
        unique_products_sold: calculate_unique_products_sold(orders),
        product_views: product_views,
        view_to_purchase_rate: calculate_view_to_purchase_rate(product_views, orders),
        top_products: top_products(start_date: start_date, end_date: end_date),
        revenue_by_category: revenue_by_category(orders),
        order_trend: order_trend(start_date, end_date)
      }
    end

    # Get top performing products
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param limit [Integer] Number of products to return
    # @return [Array<Hash>] Top products with metrics
    def top_products(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      # Get product sales from line items through product_variants
      # LineItem uses product_variant_id to reference products (not item_id/item_type)
      order_ids = business.orders.where(created_at: start_date..end_date).pluck(:id)
      
      product_sales = LineItem
        .where(lineable_type: 'Order', lineable_id: order_ids)
        .where.not(product_variant_id: nil)
        .joins(product_variant: :product)
        .group('products.id')
        .select(
          'products.id as product_id',
          'products.name as product_name',
          'products.category as product_category',
          'SUM(line_items.quantity) as total_quantity',
          'SUM(line_items.quantity * line_items.price) as total_revenue',
          'COUNT(DISTINCT line_items.lineable_id) as order_count'
        )
        .order('total_revenue DESC')
        .limit(limit)
      
      product_sales.map do |sale|
        views = product_views_for(sale.product_id, start_date, end_date)
        
        {
          product_id: sale.product_id,
          product_name: sale.product_name,
          category: sale.product_category,
          quantity_sold: sale.total_quantity.to_i,
          revenue: sale.total_revenue.to_f,
          order_count: sale.order_count.to_i,
          views: views,
          conversion_rate: views > 0 ? (sale.order_count.to_f / views * 100).round(2) : 0
        }
      end
    end

    # Get product performance by category
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Revenue and sales by category
    def revenue_by_category(orders)
      # Get line items with product info through product_variant -> product
      # LineItem uses product_variant_id to reference products (not item_id/item_type)
      order_ids = orders.pluck(:id)
      category_sales = LineItem
        .where(lineable_type: 'Order', lineable_id: order_ids)
        .where.not(product_variant_id: nil)
        .joins(product_variant: :product)
        .group('products.category')
        .select(
          'products.category',
          'SUM(line_items.quantity) as quantity',
          'SUM(line_items.quantity * line_items.price) as revenue'
        )
      
      category_sales.each_with_object({}) do |sale, hash|
        category = sale.category.presence || 'Uncategorized'
        hash[category] = {
          quantity: sale.quantity.to_i,
          revenue: sale.revenue.to_f
        }
      end
    end

    # Get product view analytics
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] View analytics
    def view_analytics(start_date: 30.days.ago, end_date: Time.current)
      clicks = business.click_events
        .for_period(start_date, end_date)
        .product_clicks
      
      {
        total_product_clicks: clicks.count,
        unique_products_viewed: clicks.where.not(target_id: nil).distinct.count(:target_id),
        unique_viewers: clicks.distinct.count(:visitor_fingerprint),
        avg_products_per_session: calculate_avg_products_per_session(clicks),
        most_viewed_products: most_viewed_products(clicks)
      }
    end

    # Get cart abandonment metrics
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Cart abandonment data
    def cart_abandonment(start_date: 30.days.ago, end_date: Time.current)
      clicks = business.click_events.for_period(start_date, end_date)
      
      add_to_cart_sessions = clicks
        .where(action: 'add_to_cart')
        .distinct
        .count(:session_id)
      
      checkout_sessions = clicks
        .where(conversion_type: 'checkout_started')
        .distinct
        .count(:session_id)
      
      purchase_sessions = business.visitor_sessions
        .for_period(start_date, end_date)
        .where(conversion_type: 'purchase')
        .count
      
      {
        cart_additions: add_to_cart_sessions,
        checkout_starts: checkout_sessions,
        purchases: purchase_sessions,
        cart_to_checkout_rate: add_to_cart_sessions > 0 ?
          (checkout_sessions.to_f / add_to_cart_sessions * 100).round(2) : 0,
        checkout_to_purchase_rate: checkout_sessions > 0 ?
          (purchase_sessions.to_f / checkout_sessions * 100).round(2) : 0,
        overall_abandonment_rate: add_to_cart_sessions > 0 ?
          ((add_to_cart_sessions - purchase_sessions).to_f / add_to_cart_sessions * 100).round(2) : 0
      }
    end

    # Get order trend data
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Array<Hash>] Daily order counts and revenue
    def order_trend(start_date, end_date)
      business.orders
        .where(created_at: start_date..end_date)
        .group("DATE(created_at)")
        .select("DATE(created_at) as date, COUNT(*) as orders, SUM(total_amount) as revenue")
        .map do |row|
          {
            date: row.date,
            orders: row.orders,
            revenue: row.revenue.to_f
          }
        end
    end

    private

    def product_page_views(start_date, end_date)
      business.page_views
        .for_period(start_date, end_date)
        .where("page_path LIKE '%/products%' OR page_type = 'products'")
        .count
    end

    def product_views_for(product_id, start_date, end_date)
      business.click_events
        .for_period(start_date, end_date)
        .where(target_type: 'Product', target_id: product_id)
        .count
    end

    def calculate_total_revenue(orders)
      orders.where(status: [:completed, :delivered]).sum(:total_amount).to_f
    end

    def calculate_average_order_value(orders)
      completed = orders.where(status: [:completed, :delivered])
      return 0.0 if completed.count.zero?

      (completed.sum(:total_amount).to_f / completed.count).round(2)
    end

    def calculate_total_items_sold(orders)
      order_ids = orders.pluck(:id)
      LineItem
        .where(lineable_type: 'Order', lineable_id: order_ids)
        .sum(:quantity)
    end

    def calculate_unique_products_sold(orders)
      order_ids = orders.pluck(:id)
      # Count unique products through product_variant -> product relationship
      LineItem
        .where(lineable_type: 'Order', lineable_id: order_ids)
        .where.not(product_variant_id: nil)
        .joins(product_variant: :product)
        .distinct
        .count('products.id')
    end

    def calculate_view_to_purchase_rate(views, orders)
      return 0.0 if views.zero?
      
      purchases = orders.where(status: [:completed, :delivered]).count
      (purchases.to_f / views * 100).round(2)
    end

    def calculate_avg_products_per_session(clicks)
      sessions = clicks.distinct.count(:session_id)
      return 0.0 if sessions.zero?
      
      (clicks.count.to_f / sessions).round(2)
    end

    def most_viewed_products(clicks, limit = 10)
      clicks
        .where.not(target_id: nil)
        .group(:target_id)
        .order('count_all DESC')
        .limit(limit)
        .count
        .map do |product_id, views|
          product = Product.find_by(id: product_id)
          next nil unless product
          
          { product_id: product_id, product_name: product.name, views: views }
        end.compact
    end
  end
end

