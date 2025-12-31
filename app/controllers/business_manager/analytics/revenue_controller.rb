# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for revenue forecasting and financial analytics
    class RevenueController < BusinessManager::BaseController
      before_action :set_revenue_service

      def index
        @forecast_30 = @revenue_service.forecast_revenue(30)
        @forecast_60 = @revenue_service.forecast_revenue(60)
        @forecast_90 = @revenue_service.forecast_revenue(90)

        @payment_aging = @revenue_service.payment_aging_report
        @refund_analysis = @revenue_service.refund_analysis(30.days)
        @revenue_breakdown = @revenue_service.revenue_by_category(30.days)
        @cash_flow = @revenue_service.cash_flow_projection(30)
      end

      def forecast
        days_ahead = params[:days]&.to_i || 30
        @forecast_data = @revenue_service.forecast_revenue(days_ahead)

        respond_to do |format|
          format.json { render json: @forecast_data }
          format.html
        end
      end

      def payment_aging
        @aging_report = @revenue_service.payment_aging_report
        @overdue_invoices = business.invoices
                                    .where.not(status: 'paid')
                                    .where('due_date < ?', Time.current)
                                    .order(due_date: :asc)
                                    .limit(50)
      end

      def refunds
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @refund_data = @revenue_service.refund_analysis(period)
        @recent_refunds = business.payments
                                  .where(status: 'refunded', created_at: period.ago..Time.current)
                                  .order(created_at: :desc)
                                  .limit(20)

        respond_to do |format|
          # Redirect to payments page with refunded status filter
          format.html { redirect_to business_manager_payments_path(status: 'refunded') }
          format.json { render json: { refund_data: @refund_data, recent_refunds: @recent_refunds } }
        end
      end

      def by_service
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        limit = params[:limit]&.to_i || 10
        @service_revenue = @revenue_service.revenue_by_service(period, limit)

        respond_to do |format|
          format.json { render json: @service_revenue }
          format.html
        end
      end

      def gross_margin
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @margin_analysis = @revenue_service.gross_margin_analysis(period)

        respond_to do |format|
          format.json { render json: @margin_analysis }
          format.html
        end
      end

      def cash_flow
        days_ahead = params[:days]&.to_i || 30
        @cash_flow_data = @revenue_service.cash_flow_projection(days_ahead)

        respond_to do |format|
          format.json { render json: @cash_flow_data }
          format.html
        end
      end

      def export
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days

        csv_data = CSV.generate do |csv|
          csv << ['Metric', 'Value']

          # Revenue forecast
          forecast = @revenue_service.forecast_revenue(30)
          csv << ['30-Day Forecast (Conservative)', forecast[:conservative]]
          csv << ['30-Day Forecast (Optimistic)', forecast[:optimistic]]
          csv << ['30-Day Forecast (Confirmed)', forecast[:confirmed]]
          csv << []

          # Payment aging
          aging = @revenue_service.payment_aging_report
          csv << ['Current (Not Overdue)', aging[:current]]
          csv << ['1-30 Days Overdue', aging[:days_30]]
          csv << ['31-60 Days Overdue', aging[:days_60]]
          csv << ['90+ Days Overdue', aging[:days_90_plus]]
          csv << ['Total Outstanding', aging[:total_outstanding]]
          csv << []

          # Revenue breakdown
          breakdown = @revenue_service.revenue_by_category(period)
          csv << ['Booking Revenue', breakdown[:bookings]]
          csv << ['Order Revenue', breakdown[:orders]]
          csv << ['Subscription Revenue', breakdown[:subscriptions]]
          csv << ['Total Revenue', breakdown[:total]]
        end

        send_data csv_data,
                  filename: "revenue-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_revenue_service
        @revenue_service = ::Analytics::RevenueForecastService.new(business)
      end

      def business
        current_business
      end
    end
  end
end
