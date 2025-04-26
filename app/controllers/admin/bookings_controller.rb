module Admin
  class BookingsController < ActiveAdmin::ResourceController
    def new
      @booking = Booking.new
      
      # First find the staff member to get the business
      if params[:staff_member_id].present?
        @staff_member = StaffMember.find_by(id: params[:staff_member_id])
        if @staff_member&.business
          @booking.business_id = @staff_member.business_id
          @booking.staff_member_id = @staff_member.id
        end
      end
      
      # Set service if provided
      if params[:service_id].present?
        @service = Service.find_by(id: params[:service_id])
        if @service
          @booking.service_id = @service.id
          
          # If we have a service, set the default times
          @booking.start_time = Time.current.beginning_of_hour + 1.hour
          @booking.end_time = @booking.start_time + @service.duration.minutes
        end
      end
      
      # Continue with the regular ActiveAdmin new action
      super
    end
  end
end 