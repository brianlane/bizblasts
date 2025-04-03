# frozen_string_literal: true

class AppointmentsController < ApplicationController
  # Skip authentication for available_slots if it's accessible to public
  # Comment this out if only authenticated users should check availability
  skip_before_action :authenticate_user!, only: [:available_slots]
  
  # GET /appointments
  def index
    @appointments = current_company_scope.appointments.includes(:service, :service_provider, :customer)
                   .order(start_time: :desc)
    
    # Filter by status if provided
    if params[:status].present? && Appointment.new.valid_status?(params[:status])
      @appointments = @appointments.where(status: params[:status])
    end
    
    # Filter by service_provider_id if provided
    if params[:service_provider_id].present?
      @appointments = @appointments.where(service_provider_id: params[:service_provider_id])
    end
    
    # Filter by customer_id if provided
    if params[:customer_id].present?
      @appointments = @appointments.where(customer_id: params[:customer_id])
    end
  end
  
  # GET /appointments/:id
  def show
    @appointment = current_company_scope.appointments.find(params[:id])
  end
  
  # GET /appointments/new
  def new
    @appointment = current_company_scope.appointments.new
    
    # Pre-fill service and service provider from params if provided
    @appointment.service_id = params[:service_id] if params[:service_id].present?
    @appointment.service_provider_id = params[:service_provider_id] if params[:service_provider_id].present?
    @appointment.customer_id = params[:customer_id] if params[:customer_id].present?
    
    # Set default start and end times if empty
    if @appointment.start_time.nil?
      @appointment.start_time = Time.current.beginning_of_hour + 1.hour
    end
    
    # Set end time based on service duration if available
    if @appointment.end_time.nil?
      service = @appointment.service
      duration = service ? service.duration_minutes : 60
      @appointment.end_time = @appointment.start_time + duration.minutes
    end
  end
  
  # POST /appointments
  def create
    @appointment = current_company_scope.appointments.new(appointment_params)
    
    if @appointment.save
      redirect_to @appointment, notice: 'Appointment was successfully created.'
    else
      render :new
    end
  end
  
  # GET /appointments/:id/edit
  def edit
    @appointment = current_company_scope.appointments.find(params[:id])
  end
  
  # PATCH/PUT /appointments/:id
  def update
    @appointment = current_company_scope.appointments.find(params[:id])
    
    if @appointment.update(appointment_params)
      redirect_to @appointment, notice: 'Appointment was successfully updated.'
    else
      render :edit
    end
  end
  
  # DELETE /appointments/:id
  def destroy
    @appointment = current_company_scope.appointments.find(params[:id])
    
    if @appointment.destroy
      redirect_to appointments_path, notice: 'Appointment was successfully deleted.'
    else
      redirect_to @appointment, alert: 'Unable to delete this appointment.'
    end
  end
  
  # GET or POST /appointments/available_slots
  def available_slots
    @date = params[:date] ? Date.parse(params[:date]) : Date.current
    @service_provider = ServiceProvider.find_by(id: params[:service_provider_id])
    @service = Service.find_by(id: params[:service_id])
    @interval = (params[:interval] || 30).to_i
    
    if @service_provider.nil?
      render json: { error: 'Service provider not found' }, status: :not_found
      return
    end
    
    # Get the available time slots using our service
    @slots = AvailabilityService.available_slots(
      @service_provider, 
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
  
  # Get the current company scope for multi-tenancy
  def current_company_scope
    ActsAsTenant.current_tenant || current_user&.company
  end
  
  # Only allow a list of trusted parameters through
  def appointment_params
    params.require(:appointment).permit(
      :service_id, 
      :service_provider_id, 
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