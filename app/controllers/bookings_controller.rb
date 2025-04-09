# frozen_string_literal: true

class BookingsController < ApplicationController
  # Skip authentication for available_slots if it's accessible to public
  # Comment this out if only authenticated users should check availability
  skip_before_action :authenticate_user!, only: [:available_slots]
  
  # GET /bookings
  def index
    @bookings = current_business_scope.bookings.includes(:service, :staff_member, :customer)
                   .order(start_time: :desc)
    
    # Filter by status if provided
    if params[:status].present? && Booking.new.valid_status?(params[:status])
      @bookings = @bookings.where(status: params[:status])
    end
    
    # Filter by staff_member_id if provided
    if params[:staff_member_id].present?
      @bookings = @bookings.where(staff_member_id: params[:staff_member_id])
    end
    
    # Filter by customer_id if provided
    if params[:customer_id].present?
      @bookings = @bookings.where(customer_id: params[:customer_id])
    end
  end
  
  # GET /bookings/:id
  def show
    @booking = current_business_scope.bookings.find(params[:id])
  end
  
  # GET /bookings/new
  def new
    @booking = current_business_scope.bookings.new
    
    # Pre-fill service and staff member from params if provided
    @booking.service_id = params[:service_id] if params[:service_id].present?
    @booking.staff_member_id = params[:staff_member_id] if params[:staff_member_id].present?
    @booking.customer_id = params[:customer_id] if params[:customer_id].present?
    
    # Set default start and end times if empty
    if @booking.start_time.nil?
      @booking.start_time = Time.current.beginning_of_hour + 1.hour
    end
    
    # Set end time based on service duration if available
    if @booking.end_time.nil?
      service = @booking.service
      duration = service ? service.duration_minutes : 60
      @booking.end_time = @booking.start_time + duration.minutes
    end
  end
  
  # POST /bookings
  def create
    @booking = current_business_scope.bookings.new(booking_params)
    
    if @booking.save
      redirect_to @booking, notice: 'Booking was successfully created.'
    else
      render :new
    end
  end
  
  # GET /bookings/:id/edit
  def edit
    @booking = current_business_scope.bookings.find(params[:id])
  end
  
  # PATCH/PUT /bookings/:id
  def update
    @booking = current_business_scope.bookings.find(params[:id])
    
    if @booking.update(booking_params)
      redirect_to @booking, notice: 'Booking was successfully updated.'
    else
      render :edit
    end
  end
  
  # DELETE /bookings/:id
  def destroy
    @booking = current_business_scope.bookings.find(params[:id])
    
    if @booking.destroy
      redirect_to bookings_path, notice: 'Booking was successfully deleted.'
    else
      redirect_to @booking, alert: 'Unable to delete this booking.'
    end
  end
  
  # GET or POST /bookings/available_slots
  def available_slots
    @date = params[:date] ? Date.parse(params[:date]) : Date.current
    @staff_member = Business.find_by(id: params[:staff_member_id])
    @service = Service.find_by(id: params[:service_id])
    @interval = (params[:interval] || 30).to_i
    
    if @staff_member.nil?
      render json: { error: 'Staff member not found' }, status: :not_found
      return
    end
    
    # Get the available time slots using our service
    @slots = AvailabilityService.available_slots(
      @staff_member, 
      @date, 
      @service, 
      interval: @interval
    )
    
    respond_to do |format|
      format.html # Render the view if HTML is requested
      format.json { render json: { date: @date, slots: @slots } }
    end
  end
  
  private
  
  # Get the current business scope for multi-tenancy
  def current_business_scope
    ActsAsTenant.current_tenant || current_user&.business
  end
  
  # Only allow a list of trusted parameters through
  def booking_params
    params.require(:booking).permit(
      :service_id, 
      :staff_member_id, 
      :customer_id, 
      :start_time, 
      :end_time, 
      :status, 
      :price, 
      :notes,
      :paid
    )
  end
end 