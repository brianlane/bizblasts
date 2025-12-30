# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for subscription and recurring revenue analytics
    class SubscriptionsController < BusinessManager::BaseController
      before_action :set_subscription_service

      def index
        @metrics_summary = @subscription_service.subscription_metrics_summary
        @mrr_breakdown = @subscription_service.mrr_breakdown
        @mrr_trend = @subscription_service.mrr_trend(12)
        @at_risk = @subscription_service.at_risk_subscriptions(50).first(10)
        @expansion = @subscription_service.expansion_revenue(30.days)
      end

      def mrr_trend
        months = params[:months]&.to_i || 12
        @trend_data = @subscription_service.mrr_trend(months)

        respond_to do |format|
          format.json { render json: @trend_data }
          format.html
        end
      end

      def churn
        period = params[:period]&.to_i&.days || 30.days
        @churn_data = {
          revenue_churn: @subscription_service.subscription_churn_rate(period),
          customer_churn: @subscription_service.customer_churn_rate(period)
        }

        respond_to do |format|
          format.json { render json: @churn_data }
          format.html
        end
      end

      def health_scores
        @health_scores = @subscription_service.subscription_health_scores

        respond_to do |format|
          format.json { render json: @health_scores }
          format.html
        end
      end

      def at_risk
        threshold = params[:threshold]&.to_i || 50
        @at_risk_subs = @subscription_service.at_risk_subscriptions(threshold)

        respond_to do |format|
          format.json { render json: @at_risk_subs }
          format.html
        end
      end

      def expansion
        period = params[:period]&.to_i&.days || 30.days
        @expansion_data = @subscription_service.expansion_revenue(period)

        respond_to do |format|
          format.json { render json: @expansion_data }
          format.html
        end
      end

      def export
        period = params[:period]&.to_i&.days || 30.days

        csv_data = CSV.generate do |csv|
          csv << ['Subscription Analytics Export']
          csv << []

          # Metrics summary
          summary = @subscription_service.subscription_metrics_summary
          csv << ['Subscription Metrics Summary']
          csv << ['Active Subscriptions', summary[:active_subscriptions]]
          csv << ['Active Customers', summary[:active_customers]]
          csv << ['MRR', summary[:mrr]]
          csv << ['ARR', summary[:arr]]
          csv << ['MRR Growth Rate', "#{summary[:mrr_growth_rate]}%"]
          csv << ['Revenue Churn Rate', "#{summary[:revenue_churn_rate]}%"]
          csv << ['Customer Churn Rate', "#{summary[:customer_churn_rate]}%"]
          csv << ['Avg Revenue per Customer', summary[:avg_revenue_per_customer]]
          csv << ['LTV', summary[:ltv]]
          csv << []

          # MRR Breakdown
          breakdown = @subscription_service.mrr_breakdown
          csv << ['MRR Breakdown']
          csv << ['New MRR', breakdown[:new_mrr]]
          csv << ['Expansion MRR', breakdown[:expansion_mrr]]
          csv << ['Contraction MRR', breakdown[:contraction_mrr]]
          csv << ['Churned MRR', breakdown[:churned_mrr]]
          csv << ['Net New MRR', breakdown[:net_new_mrr]]
          csv << []

          # At-risk subscriptions
          csv << ['At-Risk Subscriptions']
          csv << ['Customer', 'Price', 'Billing', 'Days Active', 'Health Score', 'Status']
          @subscription_service.at_risk_subscriptions(50).each do |sub|
            csv << [
              sub[:customer_name],
              sub[:subscription_price],
              sub[:billing_interval],
              sub[:days_active],
              sub[:health_score],
              sub[:status]
            ]
          end
        end

        send_data csv_data,
                  filename: "subscription-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_subscription_service
        @subscription_service = ::Analytics::SubscriptionAnalyticsService.new(business)
      end

      def business
        current_business
      end
    end
  end
end
