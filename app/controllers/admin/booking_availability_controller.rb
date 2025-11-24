# frozen_string_literal: true

module Admin
  class BookingAvailabilityController < AdminController
    def available_slots
      # Security: Validate parameters and scope to prevent enumeration
      unless params[:service_id].present? && params[:staff_member_id].present?
        flash[:error] = "Missing required parameters"
        redirect_to admin_staff_members_path and return
      end

      # Security: Find with proper validation and error handling
      @service = Service.find_by(id: params[:service_id])
      @staff_member = StaffMember.find_by(id: params[:staff_member_id])
      
      unless @service && @staff_member
        # Security: Log suspicious access attempts
        SecureLogger.warn "[SECURITY] Admin attempted to access non-existent service/staff: service_id=#{params[:service_id]}, staff_member_id=#{params[:staff_member_id]}, admin_user=#{current_admin_user&.email}, ip=#{request.remote_ip}"
        flash[:error] = "Service or staff member not found"
        redirect_to admin_staff_members_path and return
      end
      
      # Security: Validate date parameter
      begin
        @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
      rescue Date::Error
        Rails.logger.warn "[SECURITY] Invalid date parameter in admin booking availability: #{params[:date]}"
        @date = Date.today
      end
      
      @start_date = @date.beginning_of_week(:sunday)
      @end_date = @date.end_of_week(:sunday)
      
      @calendar_data = {}
      
      (@start_date..@end_date).each do |date|
        @calendar_data[date.to_s] = AvailabilityService.available_slots_for_date(
          staff_member: @staff_member,
          service: @service,
          date: date
        )
      end
    end

    def new
      # Security: Validate all parameters
      unless params[:staff_member_id].present? && params[:service_id].present? && params[:date].present? && params[:start_time].present?
        flash[:error] = "Missing required parameters"
        redirect_to admin_staff_members_path and return
      end

      @staff_member = StaffMember.find_by(id: params[:staff_member_id])
      @service = Service.find_by(id: params[:service_id])
      
      unless @staff_member && @service
        Rails.logger.warn "[SECURITY] Admin attempted to create booking with invalid service/staff: service_id=#{params[:service_id]}, staff_member_id=#{params[:staff_member_id]}"
        flash[:error] = "Service or staff member not found"
        redirect_to admin_staff_members_path and return
      end

      begin
        date = Date.parse(params[:date])
        start_time = format_datetime(date, params[:start_time])
        end_time = start_time + @service.duration.minutes
      rescue Date::Error, ArgumentError => e
        Rails.logger.warn "[SECURITY] Invalid date/time parameters in admin booking: #{e.message}"
        flash[:error] = "Invalid date or time format"
        redirect_to admin_staff_members_path and return
      end
      
      redirect_to new_admin_booking_path(
        service_id: @service.id,
        staff_member_id: @staff_member.id,
        start_time: start_time,
        end_time: end_time
      )
    end

    private

    def format_datetime(date, time_str)
      # Security: Validate time format
      unless time_str.match?(/\A\d{1,2}:\d{2}\z/)
        raise ArgumentError, "Invalid time format"
      end
      
      hours, minutes = time_str.split(':').map(&:to_i)
      
      # Security: Validate time ranges
      unless (0..23).include?(hours) && (0..59).include?(minutes)
        raise ArgumentError, "Invalid time values"
      end
      
      DateTime.new(date.year, date.month, date.day, hours, minutes)
    end
  end
end
