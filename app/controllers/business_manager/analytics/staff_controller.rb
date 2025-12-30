# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for staff performance analytics
    class StaffController < BusinessManager::BaseController
      before_action :set_staff_service

      def index
        @staff_summary = @staff_service.performance_summary
        @leaderboard = @staff_service.staff_leaderboard(30.days, sort_by: params[:sort_by]&.to_sym || :revenue)
        @capacity_analysis = @staff_service.capacity_analysis
      end

      def show
        @staff_member = business.staff_members.find(params[:id])
        @trends = @staff_service.productivity_trends(@staff_member, 90.days, interval: :week)
        @metrics = {
          bookings: @staff_member.bookings_count,
          revenue: @staff_member.total_revenue,
          completion_rate: @staff_member.completion_rate,
          cancellation_rate: @staff_member.cancellation_rate,
          no_show_rate: @staff_member.no_show_rate,
          utilization: @staff_service.calculate_utilization_rate(@staff_member, 30.days)
        }
      end

      def compare
        # Handle both array params (from checkboxes) and comma-separated string
        staff_ids = if params[:staff_ids].is_a?(Array)
                      params[:staff_ids].map(&:to_i)
                    elsif params[:staff_ids].is_a?(String)
                      params[:staff_ids].split(',').map(&:to_i)
                    else
                      []
                    end
        
        if staff_ids.any?
          staff_data = @staff_service.compare_staff(staff_ids)
          @comparison_data = { staff_members: staff_data }
        end
        @all_staff = business.staff_members.active
      end

      private

      def set_staff_service
        @staff_service = ::Analytics::StaffPerformanceService.new(business)
      end

      def business
        current_business
      end
    end
  end
end
