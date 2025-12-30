# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for customer lifecycle and churn analytics
    class CustomersController < BusinessManager::BaseController
      before_action :set_analytics_services

      def index
        @lifecycle_data = @lifecycle_service.customer_metrics_summary
        @segment_summary = @lifecycle_service.segment_summary
        @churn_stats = @churn_service.churn_statistics

        # Get top customers by CLV
        @top_customers = business.tenant_customers
                                .includes(:bookings, :orders)
                                .select { |c| c.purchase_frequency > 0 }
                                .map { |c|
                                  {
                                    customer: c,
                                    clv: @lifecycle_service.calculate_clv(c),
                                    revenue: c.total_revenue,
                                    purchases: c.purchase_frequency.to_i
                                  }
                                }
                                .sort_by { |c| -c[:clv] }
                                .first(10)
      end

      def segments
        @segments = @lifecycle_service.customer_segments_rfm.group_by { |c| c[:segment] }
        @segment_summary = @lifecycle_service.segment_summary

        respond_to do |format|
          format.html
          format.json { render json: { segments: @segments, summary: @segment_summary } }
        end
      end

      def at_risk
        threshold = params[:threshold]&.to_i || 60
        @at_risk_customers = @churn_service.at_risk_customers(threshold)
        @churn_stats = @churn_service.churn_statistics

        respond_to do |format|
          format.html
          format.json { render json: { at_risk: @at_risk_customers, stats: @churn_stats } }
        end
      end

      def show
        @customer = business.tenant_customers.find(params[:id])
        @clv = @lifecycle_service.calculate_clv(@customer)
        @churn_probability = @churn_service.predict_churn_probability(@customer)
        @risk_factors = @churn_service.send(:identify_risk_factors, @customer)
        @recommended_actions = @churn_service.recommended_actions(@customer)

        # Customer timeline data
        @purchase_history = (@customer.bookings.order(created_at: :asc).pluck(:created_at, :id, :created_at) +
                            @customer.orders.order(created_at: :asc).pluck(:created_at, :id, :created_at))
                            .sort_by { |p| p[0] }

        respond_to do |format|
          format.html
          format.json {
            render json: {
              customer: {
                id: @customer.id,
                name: @customer.full_name,
                email: @customer.email,
                clv: @clv,
                total_revenue: @customer.total_revenue,
                purchase_frequency: @customer.purchase_frequency,
                days_since_last_purchase: @customer.days_since_last_purchase,
                churn_probability: @churn_probability,
                risk_factors: @risk_factors,
                recommended_actions: @recommended_actions
              }
            }
          }
        end
      end

      def export
        @customers = business.tenant_customers.includes(:bookings, :orders)

        csv_data = CSV.generate(headers: true) do |csv|
          csv << [
            'Customer ID',
            'Name',
            'Email',
            'Total Revenue',
            'Purchase Count',
            'Last Purchase',
            'Days Since Purchase',
            'Customer Lifetime Value',
            'Churn Probability',
            'Segment'
          ]

          @customers.each do |customer|
            next if customer.purchase_frequency.zero?

            segments = @lifecycle_service.customer_segments_rfm
            segment_data = segments.find { |s| s[:customer_id] == customer.id }

            csv << [
              customer.id,
              customer.full_name,
              customer.email,
              customer.total_revenue,
              customer.purchase_frequency.to_i,
              customer.last_purchase_at&.strftime('%Y-%m-%d'),
              customer.days_since_last_purchase,
              @lifecycle_service.calculate_clv(customer),
              @churn_service.predict_churn_probability(customer),
              segment_data&.dig(:segment) || 'N/A'
            ]
          end
        end

        send_data csv_data, filename: "customer-analytics-#{Date.current}.csv"
      end

      private

      def set_analytics_services
        @lifecycle_service = ::Analytics::CustomerLifecycleService.new(business)
        @churn_service = ::Analytics::ChurnPredictionService.new(business)
      end

      def business
        current_business
      end
    end
  end
end
