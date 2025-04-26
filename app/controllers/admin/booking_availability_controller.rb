# frozen_string_literal: true

module Admin
  class BookingAvailabilityController < AdminController
    def available_slots
      @service = Service.find_by(id: params[:service_id])
      @staff_member = StaffMember.find_by(id: params[:staff_member_id])
      
      unless @service && @staff_member
        flash[:error] = "Service or staff member not found"
        redirect_to admin_staff_members_path and return
      end
      
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
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
      @staff_member = StaffMember.find(params[:staff_member_id])
      @service = Service.find(params[:service_id])
      date = Date.parse(params[:date])
      start_time = format_datetime(date, params[:start_time])
      end_time = start_time + @service.duration.minutes
      
      redirect_to new_admin_booking_path(
        service_id: @service.id,
        staff_member_id: @staff_member.id,
        start_time: start_time,
        end_time: end_time
      )
    end

    private

    def format_datetime(date, time_str)
      hours, minutes = time_str.split(':').map(&:to_i)
      DateTime.new(date.year, date.month, date.day, hours, minutes)
    end
  end
end
