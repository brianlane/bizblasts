# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for operational efficiency and booking analytics
    class OperationsController < BusinessManager::BaseController
      before_action :set_operations_service

      def index
        @no_show_data = @operations_service.no_show_analysis(30.days)
        @cancellation_data = @operations_service.cancellation_analysis(30.days)
        @peak_hours = @operations_service.peak_hours_heatmap(90.days)
        @fulfillment_metrics = @operations_service.fulfillment_metrics(30.days)
        @lead_time_dist = @operations_service.lead_time_distribution(30.days)
      end

      def no_shows
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @no_show_data = @operations_service.no_show_analysis(period)
        @no_show_bookings = business.bookings
                                    .where(status: :no_show, created_at: period.ago..Time.current)
                                    .includes(:service, :tenant_customer, :staff_member)
                                    .order(start_time: :desc)
                                    .limit(50)

        respond_to do |format|
          # Redirect to bookings page with no_show status filter
          format.html { redirect_to business_manager_bookings_path(status: 'no_show') }
          format.json { render json: { no_show_data: @no_show_data, bookings: @no_show_bookings } }
        end
      end

      def peak_hours
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 90.days
        heatmap_result = @operations_service.peak_hours_heatmap(period)

        # Convert 2D array to hash format: { monday: { 8: 5, 9: 10 }, ... }
        days = [:sunday, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
        @heatmap_data = {}

        heatmap_result[:heatmap].each_with_index do |day_data, day_index|
          day_name = days[day_index]
          @heatmap_data[day_name] = {}
          day_data.each_with_index do |count, hour|
            @heatmap_data[day_name][hour] = count
          end
        end

        respond_to do |format|
          format.json { render json: @heatmap_data }
          format.html
        end
      end

      def capacity
        @capacity_analysis = @operations_service.service_capacity_analysis(30.days)

        respond_to do |format|
          format.json { render json: @capacity_analysis }
          format.html
        end
      end

      def staff_idle_time
        @staff_member = business.staff_members.find(params[:staff_id]) if params[:staff_id]
        @date = params[:date]&.to_date || Date.current

        if @staff_member
          @idle_analysis = @operations_service.idle_time_analysis(@staff_member, @date)
        end

        @all_staff = business.staff_members.active
      end

      def lead_time
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days
        @lead_time_data = @operations_service.lead_time_distribution(period)

        respond_to do |format|
          format.json { render json: @lead_time_data }
          format.html
        end
      end

      def export
        period_days = params[:period]&.to_i
        period = (period_days && period_days > 0) ? period_days.days : 30.days

        csv_data = CSV.generate do |csv|
          csv << ['Metric', 'Value']

          # No-show analysis
          no_shows = @operations_service.no_show_analysis(period)
          csv << ['No-Show Count', no_shows[:no_show_count]]
          csv << ['No-Show Rate', "#{no_shows[:no_show_rate]}%"]
          csv << ['Estimated Lost Revenue', no_shows[:estimated_lost_revenue]]
          csv << []

          # Cancellation analysis
          cancellations = @operations_service.cancellation_analysis(period)
          csv << ['Cancellation Count', cancellations[:cancellation_count]]
          csv << ['Cancellation Rate', "#{cancellations[:cancellation_rate]}%"]
          csv << ['Avg Cancellation Lead Time (hours)', cancellations[:avg_cancellation_lead_time]]
          csv << []

          # Fulfillment metrics
          fulfillment = @operations_service.fulfillment_metrics(period)
          csv << ['Total Completed Bookings', fulfillment[:total_completed]]
          csv << ['Avg Duration (minutes)', fulfillment[:avg_duration]]
          csv << ['Completion Rate', "#{fulfillment[:completion_rate]}%"]
          csv << ['Avg Lead Time (days)', fulfillment[:avg_lead_time]]
          csv << []

          # Lead time distribution
          lead_time = @operations_service.lead_time_distribution(period)
          csv << ['Avg Lead Time (days)', lead_time[:avg_lead_time_days]]
          csv << ['Same-Day Bookings', lead_time[:same_day]]
          csv << ['Next-Day Bookings', lead_time[:next_day]]
          csv << ['Within Week', lead_time[:within_week]]
          csv << ['Over Week', lead_time[:over_week]]
        end

        send_data csv_data,
                  filename: "operational-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_operations_service
        @operations_service = ::Analytics::OperationalEfficiencyService.new(business)
      end

      def business
        current_business
      end
    end
  end
end
