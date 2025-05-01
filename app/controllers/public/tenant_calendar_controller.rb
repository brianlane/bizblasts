# frozen_string_literal: true

module Public
  class TenantCalendarController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_authorized_user
    before_action :set_business
    
    def index
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @services = @business.services.active
      
      # Selected service if provided
      @service = @business.services.find_by(id: params[:service_id]) if params[:service_id].present?
      
      # If service is selected, fetch initial data for the month using BookingService
      if @service.present?
        @calendar_data = BookingService.generate_calendar_data(
          date: @date,
          service: @service,
          tenant: @business
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
          service: @service,
          date: start_date, # Use start_date to determine the month range internally if needed
          tenant: @business
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
    
    def ensure_authorized_user
      unless current_user&.client? || current_user&.staff? || current_user&.manager? 
        flash[:alert] = 'You must be logged in as a client, staff member, or manager to access this page.'
        redirect_to tenant_root_path
      end
    end
  end
end 