# frozen_string_literal: true

module Public
  class TenantCalendarController < Public::BaseController
    after_action :no_store!
    skip_before_action :authenticate_user!
    before_action :set_business
    
    def index
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @services = @business.services.active
      
      # Selected service if provided
      @service = @business.services.find_by(id: params[:service_id]) if params[:service_id].present?
      

      if @service.present?
        # Build a month-centered 5-week calendar grid that properly shows the target month
        # This ensures the full target month is visible with appropriate padding from adjacent months
        
        # Start with the target month's first day
        month_start = @date.beginning_of_month
        month_end = @date.end_of_month
        
        # Find the Monday that starts the week containing the first day of the month
        @calendar_start_date = month_start.beginning_of_week(:monday)
        
        # Calculate how many weeks we need to show the full month
        weeks_needed = ((month_end - @calendar_start_date).to_i / 7.0).ceil
        
        # Ensure we always show exactly 5 weeks for consistency
        weeks_to_show = [weeks_needed, 5].max
        @calendar_end_date = @calendar_start_date + (weeks_to_show * 7 - 1).days
        
        # Use the target date as the calendar base for proper month context
        @calendar_base_date = @date
        
        @calendar_data = BookingService.generate_calendar_data(
          service:    @service,
          date:       @date,
          tenant:     @business,
          start_date: @calendar_start_date,
          end_date:   @calendar_end_date
        )
      else
        @calendar_data = {} # Initialize empty if no service selected
      end
    end
    
    def available_slots
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @service = @business.services.find_by(id: params[:service_id])
      @interval = (params[:interval] || 30).to_i
      
      if @service.nil?
        render json: { error: 'Service not found' }, status: :not_found
        return
      end
      
      # For date range requests (used by calendar initial load)
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        
        # Get availability data for the date range for the service (all staff)
        @calendar_data = BookingService.generate_calendar_data(
          service:    @service,
          date:       start_date,
          tenant:     @business,
          start_date: start_date,
          end_date:   end_date
        )
        
        respond_to do |format|
          format.html { render partial: 'calendar_data', locals: { calendar_data: @calendar_data } } # Example if partial rendering needed
          format.json { render json: @calendar_data }
        end
        return
      end
      
      # Get the available time slots for a specific day using BookingService
      @available_slots = BookingService.fetch_available_slots(
        date: @date,
        service: @service,
        interval: @interval,
        tenant: @business
      )
      
      respond_to do |format|
        format.html { render partial: 'available_slots', locals: { date: @date, slots: @available_slots } } # Example if partial rendering needed
        format.json { render json: { @date.to_s => @available_slots } }
      end
    end
    
    def staff_availability
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @service = @business.services.find_by(id: params[:service_id])
      
      if @service.nil?
        flash.now[:alert] = 'Service not found'
        @available_staff = []
        return
      end
      
      # Get staff availability using BookingService
      @staff_availability = BookingService.fetch_staff_availability(
        service: @service,
        date: @date,
        tenant: @business
      )
      
      respond_to do |format|
        format.html # Render the view
        format.json { render json: { date: @date, staff_availability: @staff_availability } }
      end
    end
    
    private
    
    def set_business
      # Find the business through the tenant setup from the subdomain
      @business = ActsAsTenant.current_tenant
      
      if @business
        Rails.logger.debug "[Public::TenantCalendarController] Business tenant found: #{@business.name} (ID: #{@business.id})"
      else
        # Try to find business via hostname
        hostname = request.subdomain
        @business = Business.find_by(hostname: hostname)
        
        if @business
          Rails.logger.debug "[Public::TenantCalendarController] Business found via hostname: #{@business.name} (ID: #{@business.id})"
          # Set the tenant for this request
          ActsAsTenant.current_tenant = @business
        else
          Rails.logger.error "[Public::TenantCalendarController] No business tenant found for subdomain: #{hostname}"
          # Create redirect URL to main domain
          base_domain = request.domain
          port_string = request.port == 80 || request.port == 443 ? '' : ":#{request.port}"
          redirect_url = "#{request.protocol}#{base_domain}#{port_string}/book"
          
          redirect_to redirect_url, allow_other_host: true, alert: "Unable to find business information."
          return false
        end
      end
    end
  end
end 