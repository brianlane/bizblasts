# frozen_string_literal: true

module Analytics
  # Service for revenue forecasting and financial intelligence
  class RevenueForecastService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Forecast revenue for specified days ahead using multiple methods
    def forecast_revenue(days_ahead = 30)
      historical_data = calculate_daily_revenue_history(90.days)

      return zero_forecast if historical_data.empty?

      moving_avg = historical_data.sum / historical_data.count
      trend = calculate_revenue_trend(historical_data)
      confirmed_revenue = future_bookings_revenue(days_ahead.days)

      {
        conservative: (moving_avg * days_ahead).round(2),
        optimistic: ((moving_avg + trend) * days_ahead).round(2),
        confirmed: confirmed_revenue.round(2),
        daily_average: moving_avg.round(2),
        trend_direction: trend > 0 ? 'up' : trend < 0 ? 'down' : 'stable'
      }
    end

    # Payment aging report (30/60/90 days)
    def payment_aging_report
      invoices = business.invoices.where.not(status: 'paid')

      {
        current: invoices.where('due_date > ?', Time.current).sum(:amount).to_f,
        days_30: invoices.where(due_date: 30.days.ago..Time.current).sum(:amount).to_f,
        days_60: invoices.where(due_date: 60.days.ago..30.days.ago).sum(:amount).to_f,
        days_90_plus: invoices.where('due_date < ?', 90.days.ago).sum(:amount).to_f,
        total_outstanding: invoices.sum(:amount).to_f,
        overdue_count: invoices.where('due_date < ?', Time.current).count
      }
    end

    # Refund analysis
    def refund_analysis(period = 30.days)
      all_payments = business.payments.where(created_at: period.ago..Time.current)
      total_payments = all_payments.where(status: :completed).sum(:amount).to_f
      refunds = all_payments.where(status: :refunded).sum(:amount).to_f

      {
        total_refunds: refunds,
        total_payments: total_payments,
        refund_rate: total_payments > 0 ? ((refunds / total_payments) * 100).round(2) : 0,
        refund_count: all_payments.where(status: :refunded).count,
        avg_refund_amount: all_payments.where(status: :refunded).average(:amount)&.round(2) || 0
      }
    end

    # Revenue breakdown by category
    def revenue_by_category(period = 30.days)
      booking_revenue = business.bookings
                               .where(created_at: period.ago..Time.current)
                               .joins(invoice: :payments)
                               .where(payments: { status: :completed })
                               .sum('payments.amount').to_f

      order_revenue = business.orders
                             .where(created_at: period.ago..Time.current)
                             .joins(:payments)
                             .where(payments: { status: :completed })
                             .sum('payments.amount').to_f

      subscription_revenue = business.subscription_transactions
                                    .where(created_at: period.ago..Time.current, status: :completed)
                                    .sum(:amount).to_f

      total = booking_revenue + order_revenue + subscription_revenue

      {
        bookings: booking_revenue,
        orders: order_revenue,
        subscriptions: subscription_revenue,
        total: total,
        percentages: {
          bookings: total > 0 ? ((booking_revenue / total) * 100).round(1) : 0,
          orders: total > 0 ? ((order_revenue / total) * 100).round(1) : 0,
          subscriptions: total > 0 ? ((subscription_revenue / total) * 100).round(1) : 0
        }
      }
    end

    # Revenue by service
    def revenue_by_service(period = 30.days, limit = 10)
      business.services
              .joins(bookings: { invoice: :payments })
              .where('bookings.created_at >= ?', period.ago)
              .where(payments: { status: :completed })
              .group('services.id', 'services.name')
              .select('services.name, SUM(payments.amount) as revenue, COUNT(bookings.id) as booking_count')
              .order('revenue DESC')
              .limit(limit)
              .map { |s| { name: s.name, revenue: s.revenue.to_f, bookings: s.booking_count } }
    end

    # Gross margin analysis (requires cost tracking)
    def gross_margin_analysis(period = 30.days)
      services_with_cost = business.services.where.not(cost_price: nil)
      products_with_cost = business.products.where.not(cost_price: nil)

      # Service margins
      service_revenue = 0
      service_cost = 0

      services_with_cost.each do |service|
        bookings = service.bookings.where(created_at: period.ago..Time.current)
        revenue = bookings.joins(invoice: :payments).where(payments: { status: :completed }).sum('payments.amount').to_f
        cost = service.cost_price.to_f * bookings.count

        service_revenue += revenue
        service_cost += cost
      end

      # Product margins
      product_revenue = 0
      product_cost = 0

      products_with_cost.each do |product|
        orders = business.orders
                        .joins(:line_items)
                        .where(created_at: period.ago..Time.current, line_items: { itemable: product })

        revenue = orders.joins(:payments).where(payments: { status: :completed }).sum('payments.amount').to_f
        quantity = orders.joins(:line_items).where(line_items: { itemable: product }).sum('line_items.quantity')
        cost = product.cost_price.to_f * quantity

        product_revenue += revenue
        product_cost += cost
      end

      total_revenue = service_revenue + product_revenue
      total_cost = service_cost + product_cost
      gross_profit = total_revenue - total_cost

      {
        total_revenue: total_revenue.round(2),
        total_cost: total_cost.round(2),
        gross_profit: gross_profit.round(2),
        gross_margin: total_revenue > 0 ? ((gross_profit / total_revenue) * 100).round(2) : 0,
        by_category: {
          services: {
            revenue: service_revenue.round(2),
            cost: service_cost.round(2),
            profit: (service_revenue - service_cost).round(2)
          },
          products: {
            revenue: product_revenue.round(2),
            cost: product_cost.round(2),
            profit: (product_revenue - product_cost).round(2)
          }
        }
      }
    end

    # Cash flow projection
    def cash_flow_projection(days_ahead = 30)
      # Confirmed incoming (scheduled bookings with deposits/full payments)
      confirmed_bookings = business.bookings
                                  .where('start_time BETWEEN ? AND ?', Time.current, days_ahead.days.from_now)
                                  .joins(invoice: :payments)
                                  .where(payments: { status: :completed })
                                  .sum('payments.amount').to_f

      # Pending invoices due
      due_invoices = business.invoices
                            .where(status: 'sent')
                            .where('due_date BETWEEN ? AND ?', Time.current, days_ahead.days.from_now)
                            .sum(:amount).to_f

      # Recurring subscriptions
      active_subs = business.customer_subscriptions.active.sum(:subscription_price).to_f
      periods_in_range = (days_ahead / 30.0).ceil
      recurring_revenue = active_subs * periods_in_range

      # Forecast based on historical average
      historical_avg = calculate_daily_revenue_history(30.days).sum / 30.0
      projected_revenue = historical_avg * days_ahead

      {
        confirmed: confirmed_bookings.round(2),
        pending_invoices: due_invoices.round(2),
        recurring_subscriptions: recurring_revenue.round(2),
        projected: projected_revenue.round(2),
        total_expected: (confirmed_bookings + due_invoices + recurring_revenue).round(2)
      }
    end

    private

    def calculate_daily_revenue_history(period)
      date_range = period.ago.to_date..Date.current

      date_range.map do |date|
        business.payments
                .where(created_at: date.beginning_of_day..date.end_of_day, status: :completed)
                .sum(:amount).to_f
      end
    end

    def calculate_revenue_trend(historical_data)
      return 0 if historical_data.length < 2

      # Simple linear trend
      n = historical_data.length
      x_sum = (0...n).sum
      y_sum = historical_data.sum
      xy_sum = historical_data.each_with_index.sum { |y, x| x * y }
      x_squared_sum = (0...n).sum { |x| x * x }

      slope = (n * xy_sum - x_sum * y_sum).to_f / (n * x_squared_sum - x_sum * x_sum)
      slope.round(2)
    end

    def future_bookings_revenue(period_ahead)
      business.bookings
              .where('start_time BETWEEN ? AND ?', Time.current, period_ahead.from_now)
              .joins(invoice: :payments)
              .where(payments: { status: :completed })
              .sum('payments.amount').to_f
    end

    def zero_forecast
      {
        conservative: 0,
        optimistic: 0,
        confirmed: 0,
        daily_average: 0,
        trend_direction: 'stable'
      }
    end
  end
end
