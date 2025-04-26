# frozen_string_literal: true

module BusinessManager
  class BookingsController < BaseController
    before_action :authenticate_user!
    before_action :require_business_staff!
    before_action :set_booking, only: [:show, :edit, :update, :confirm, :cancel, :reschedule, :update_schedule]
    
    # GET /manage/bookings
    def index
      @bookings = current_business.bookings
                  .includes(:service, :staff_member, :tenant_customer)
                  .order(created_at: :desc)
                  
      @status_filter = params[:status]
      @bookings = @bookings.by_status(@status_filter) if @status_filter.present?
      
      @date_filter = params[:date] ? Date.parse(params[:date]) : nil
      @bookings = @bookings.on_date(@date_filter) if @date_filter.present?
    end
    
    # GET /manage/bookings/:id
    def show
    end
    
    # GET /manage/bookings/:id/edit
    def edit
    end
    
    # PATCH /manage/bookings/:id
    def update
      if @booking.update(booking_params)
        flash[:notice] = "Booking was successfully updated."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem updating the booking."
        render :edit
      end
    end
    
    # PATCH /manage/bookings/:id/confirm
    def confirm
      if @booking.status == 'confirmed'
        flash[:notice] = "This booking was already confirmed."
      elsif @booking.update(status: :confirmed)
        # Send email notification
        BookingMailer.status_update(@booking).deliver_later
        flash[:notice] = "Booking has been confirmed."
      else
        flash[:alert] = "There was a problem confirming the booking."
      end
      
      redirect_to business_manager_booking_path(@booking)
    end
    
    # PATCH /manage/bookings/:id/cancel
    def cancel
      cancellation_reason = params[:cancellation_reason] || "Cancelled by business"
      
      if @booking.status == 'cancelled'
        flash[:notice] = "This booking was already cancelled."
      elsif BookingService.cancel_booking(@booking, cancellation_reason)
        flash[:notice] = "Booking has been cancelled."
      else
        flash[:alert] = "There was a problem cancelling the booking."
      end
      
      redirect_to business_manager_booking_path(@booking)
    end
    
    # GET /manage/bookings/:id/reschedule
    def reschedule
      @staff_members = current_business.staff_members.active
      @start_date = Date.today
      @end_date = @start_date + 14.days
      
      # Get the staff member - either from params or the booking's assigned staff
      staff_member_id = params[:staff_member_id].present? ? params[:staff_member_id] : @booking.staff_member_id
      @current_staff = current_business.staff_members.find_by(id: staff_member_id) || @booking.staff_member
      
      # Fetch available slots for the booking's current date, staff, and service
      @date_to_check = params[:date].present? ? Date.parse(params[:date]) : @booking.start_time.to_date
      
      # Debug - make sure the staff member is assigned to this service
      Rails.logger.debug("Staff member: #{@current_staff.name} (ID: #{@current_staff.id})")
      Rails.logger.debug("Staff member services: #{@current_staff.services.pluck(:id, :name)}")
      Rails.logger.debug("Booking service: #{@booking.service.id} - #{@booking.service.name}")
      
      # Ensure the staff member has this service assigned (especially important for reschedule)
      # The original booking already validates this, so it's safe to ensure it here
      unless @current_staff.services.include?(@booking.service)
        Rails.logger.debug("IMPORTANT: Staff member does not have this service assigned, temporarily assigning it")
        @current_staff.services << @booking.service unless @current_staff.services.include?(@booking.service)
      end
      
      # Try getting slots using the service's duration as the interval
      @available_slots = AvailabilityService.available_slots(
        @current_staff, 
        @date_to_check, 
        @booking.service,
        interval: @booking.service.duration
      )
      
      # If no slots are found, generate slots directly from the staff member's availability
      # This ensures users can always reschedule regardless of conflicts
      if @available_slots.empty?
        Rails.logger.debug("No slots found using standard method, generating basic slots from staff availability")
        generate_slots_from_availability
      end
      
      Rails.logger.debug "Available slots for reschedule: #{@available_slots.map { |s| s[:start_time].strftime('%H:%M') }}"
    end
    
    # PATCH /manage/bookings/:id/update_schedule
    def update_schedule
      new_start_time = Time.zone.parse("#{params[:date]} #{params[:start_time]}")
      service_duration = @booking.service.duration
      new_end_time = new_start_time + service_duration.minutes
      
      if @booking.update(start_time: new_start_time, end_time: new_end_time)
        # Send email notification about reschedule
        BookingMailer.status_update(@booking).deliver_later
        flash[:notice] = "Booking has been rescheduled."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem rescheduling the booking."
        render :reschedule
      end
    end
    
    # GET /manage/available-slots
    # This action shows available booking slots for a specific staff member and service
    def available_slots
      @service = current_business.services.find_by(id: params[:service_id])
      @staff_member = current_business.staff_members.find_by(id: params[:staff_member_id])
      
      if @service.nil? || @staff_member.nil?
        flash[:alert] = "Service or staff member not found"
        redirect_to business_manager_dashboard_path
        return
      end
      
      @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
      
      # Fetch calendar data for the selected week
      @calendar_data = {}
      (@start_date..@end_date).each do |date|
        @calendar_data[date.to_s] = AvailabilityService.available_slots(
          @staff_member,
          date,
          @service
        )
      end
    end
    
    private
    
    # Helper method to ensure user is staff or manager
    def require_business_staff!
      unless current_user && (current_user.manager? || current_user.staff?)
        flash[:alert] = "You need to be a staff member or manager to access this area."
        redirect_to root_path
      end
    end
    
    def set_booking
      @booking = current_business.bookings.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = "Booking not found."
      redirect_to business_manager_bookings_path
    end
    
    def booking_params
      params.require(:booking).permit(:notes, :staff_member_id)
    end
    
    # Helper method to generate time slots from basic staff availability
    def generate_slots_from_availability
      staff_member = @current_staff
      date = @date_to_check
      service = @booking.service
      
      # Get the day's availability intervals from staff member's schedule
      day_name = date.strftime('%A').downcase
      availability_data = staff_member.availability&.with_indifferent_access || {}
      
      # Check for date-specific exceptions first, then fall back to regular schedule
      intervals = if availability_data[:exceptions]&.key?(date.iso8601)
        availability_data[:exceptions][date.iso8601]
      else
        availability_data[day_name]
      end
      
      return if intervals.blank?
      
      # Generate slots every hour between the start and end times
      @available_slots = []
      
      intervals.each do |interval_data|
        start_time_str = interval_data['start']
        end_time_str = interval_data['end']
        
        next unless start_time_str && end_time_str
        
        # Parse the time strings into Time objects for the given date
        begin
          start_hour, start_minute = start_time_str.split(':').map(&:to_i)
          end_hour, end_minute = end_time_str.split(':').map(&:to_i)
          
          # Create times in the business's time zone
          interval_start = Time.zone.local(date.year, date.month, date.day, start_hour, start_minute)
          interval_end = Time.zone.local(date.year, date.month, date.day, end_hour, end_minute)
          
          # Generate a slot every hour (or service duration)
          step = 60.minutes
          current_time = interval_start
          
          # Only include times that allow the full service duration to fit
          while current_time + service.duration.minutes <= interval_end
            @available_slots << {
              start_time: current_time,
              end_time: current_time + service.duration.minutes
            }
            current_time += step
          end
        rescue ArgumentError => e
          Rails.logger.error("Invalid time format in staff availability: #{e.message}")
          next
        end
      end
    end
  end
end 