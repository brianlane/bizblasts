# frozen_string_literal: true

module Analytics
  # Service for subscription and recurring revenue analytics
  class SubscriptionAnalyticsService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Calculate Monthly Recurring Revenue (MRR)
    def calculate_mrr(date = Date.current)
      active_subscriptions = business.customer_subscriptions
                                     .active
                                     .where('start_date <= ?', date)

      active_subscriptions.sum do |subscription|
        normalize_to_monthly(subscription.subscription_price, subscription.billing_interval)
      end.round(2)
    end

    # MRR growth rate
    def mrr_growth_rate(period = 30.days)
      current_mrr = calculate_mrr(Date.current)
      previous_mrr = calculate_mrr(period.ago.to_date)

      return 0 if previous_mrr.zero?

      (((current_mrr - previous_mrr) / previous_mrr) * 100).round(2)
    end

    # MRR breakdown by components
    def mrr_breakdown
      current_month_start = Time.current.beginning_of_month
      previous_month_start = 1.month.ago.beginning_of_month

      # New MRR from subscriptions started this month
      new_mrr = business.customer_subscriptions
                        .where(start_date: current_month_start..Time.current)
                        .sum { |s| normalize_to_monthly(s.subscription_price, s.billing_interval) }

      # Expansion MRR from upgrades
      expansions = business.subscription_transactions
                           .where(transaction_type: 'upgrade', created_at: current_month_start..Time.current)
      expansion_mrr = expansions.sum(:amount_change).to_f

      # Contraction MRR from downgrades
      contractions = business.subscription_transactions
                             .where(transaction_type: 'downgrade', created_at: current_month_start..Time.current)
      contraction_mrr = contractions.sum(:amount_change).abs.to_f

      # Churned MRR from cancellations
      churned = business.customer_subscriptions
                        .where(cancelled_at: current_month_start..Time.current)
      churned_mrr = churned.sum { |s| normalize_to_monthly(s.subscription_price, s.billing_interval) }

      {
        new_mrr: new_mrr.round(2),
        expansion_mrr: expansion_mrr.round(2),
        contraction_mrr: contraction_mrr.round(2),
        churned_mrr: churned_mrr.round(2),
        net_new_mrr: (new_mrr + expansion_mrr - contraction_mrr - churned_mrr).round(2)
      }
    end

    # Subscription churn rate (revenue churn)
    def subscription_churn_rate(period = 30.days)
      start_date = period.ago.beginning_of_month
      end_date = start_date.end_of_month

      # MRR at start of period
      start_mrr = calculate_mrr(start_date.to_date)
      return 0 if start_mrr.zero?

      # Churned MRR during period
      churned_subscriptions = business.customer_subscriptions
                                      .where(cancelled_at: start_date..end_date)

      churned_mrr = churned_subscriptions.sum do |subscription|
        normalize_to_monthly(subscription.subscription_price, subscription.billing_interval)
      end

      ((churned_mrr / start_mrr) * 100).round(2)
    end

    # Customer churn rate (logo churn)
    def customer_churn_rate(period = 30.days)
      start_date = period.ago.beginning_of_month
      end_date = start_date.end_of_month

      # Active customers at start
      start_count = business.customer_subscriptions
                            .active
                            .where('start_date <= ?', start_date)
                            .distinct
                            .count(:tenant_customer_id)

      return 0 if start_count.zero?

      # Churned customers
      churned_count = business.customer_subscriptions
                              .where(cancelled_at: start_date..end_date)
                              .distinct
                              .count(:tenant_customer_id)

      ((churned_count.to_f / start_count) * 100).round(2)
    end

    # Customer expansion revenue (upsells and add-ons)
    def expansion_revenue(period = 30.days)
      expansions = business.subscription_transactions
                           .where(transaction_type: 'upgrade', created_at: period.ago..Time.current)

      {
        total_expansion: expansions.sum(:amount_change).to_f.round(2),
        expansion_count: expansions.count,
        avg_expansion: expansions.any? ? (expansions.sum(:amount_change).to_f / expansions.count).round(2) : 0
      }
    end

    # Subscription lifetime value
    def subscription_ltv
      active_subscriptions = business.customer_subscriptions.active

      return 0 if active_subscriptions.empty?

      # Calculate average subscription value
      avg_mrr_per_customer = calculate_mrr / active_subscriptions.distinct.count(:tenant_customer_id)

      # Calculate average customer lifespan (in months)
      cancelled_subscriptions = business.customer_subscriptions.where.not(cancelled_at: nil)
      if cancelled_subscriptions.any?
        avg_lifespan_months = cancelled_subscriptions.average('EXTRACT(EPOCH FROM (cancelled_at - start_date)) / 2592000').to_f
      else
        avg_lifespan_months = 12 # Default estimate if no churn data
      end

      (avg_mrr_per_customer * avg_lifespan_months).round(2)
    end

    # Failed payment recovery rate
    def failed_payment_recovery_rate(period = 30.days)
      failed_payments = business.payments
                                .where(status: 'failed', created_at: period.ago..Time.current)
                                .where(payable_type: 'CustomerSubscription')

      total_failed = failed_payments.count
      return 0 if total_failed.zero?

      # Payments that were eventually recovered
      recovered = failed_payments.select do |payment|
        # Check if a successful payment was made for the same subscription shortly after
        business.payments
                .where(payable: payment.payable, status: 'completed')
                .where('created_at > ? AND created_at <= ?', payment.created_at, payment.created_at + 7.days)
                .exists?
      end

      ((recovered.count.to_f / total_failed) * 100).round(2)
    end

    # Subscription health scores
    def subscription_health_scores
      subscriptions = business.customer_subscriptions.active

      subscriptions.map do |subscription|
        score = calculate_health_score(subscription)

        {
          subscription_id: subscription.id,
          customer_name: subscription.tenant_customer.full_name,
          subscription_price: subscription.subscription_price,
          billing_interval: subscription.billing_interval,
          days_active: (Time.current - subscription.start_date).to_i / 1.day,
          health_score: score,
          status: health_status(score)
        }
      end.sort_by { |s| s[:health_score] }
    end

    # At-risk subscriptions identification
    def at_risk_subscriptions(threshold = 50)
      health_scores = subscription_health_scores
      health_scores.select { |s| s[:health_score] < threshold }
    end

    # Subscription metrics summary
    def subscription_metrics_summary
      active_subs = business.customer_subscriptions.active
      current_mrr = calculate_mrr

      {
        active_subscriptions: active_subs.count,
        active_customers: active_subs.distinct.count(:tenant_customer_id),
        mrr: current_mrr,
        arr: (current_mrr * 12).round(2), # Annual Recurring Revenue
        mrr_growth_rate: mrr_growth_rate(30.days),
        revenue_churn_rate: subscription_churn_rate(30.days),
        customer_churn_rate: customer_churn_rate(30.days),
        avg_revenue_per_customer: active_subs.any? ? (current_mrr / active_subs.distinct.count(:tenant_customer_id)).round(2) : 0,
        ltv: subscription_ltv
      }
    end

    # MRR trend over time (last 12 months)
    def mrr_trend(months = 12)
      (0...months).map do |i|
        date = i.months.ago.beginning_of_month.to_date
        {
          month: date.strftime('%b %Y'),
          mrr: calculate_mrr(date)
        }
      end.reverse
    end

    private

    def normalize_to_monthly(amount, interval)
      case interval
      when 'weekly'
        amount * 4.33 # Average weeks per month
      when 'monthly'
        amount
      when 'quarterly'
        amount / 3.0
      when 'yearly'
        amount / 12.0
      else
        amount
      end
    end

    def calculate_health_score(subscription)
      score = 100

      # Factor 1: Payment failures (deduct 20 points per failure)
      failed_payments = business.payments
                                .where(payable: subscription, status: 'failed', created_at: 90.days.ago..Time.current)
                                .count
      score -= [failed_payments * 20, 40].min

      # Factor 2: Account age (newer subscriptions are higher risk)
      days_active = (Time.current - subscription.start_date).to_i / 1.day
      if days_active < 30
        score -= 20
      elsif days_active < 90
        score -= 10
      end

      # Factor 3: Customer engagement (if available)
      customer = subscription.tenant_customer
      days_since_last_activity = customer.last_activity_at ? (Time.current - customer.last_activity_at).to_i / 1.day : nil
      if days_since_last_activity && days_since_last_activity > 30
        score -= 20
      end

      # Factor 4: Downgrade history
      downgrades = business.subscription_transactions
                           .where(subscription: subscription, transaction_type: 'downgrade')
                           .count
      score -= [downgrades * 10, 20].min

      [score, 0].max
    end

    def health_status(score)
      case score
      when 80..100 then 'healthy'
      when 50..79 then 'at_risk'
      else 'critical'
      end
    end
  end
end
