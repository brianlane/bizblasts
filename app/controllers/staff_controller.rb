class StaffController < ApplicationController
  before_action :set_staff_member, only: [:show, :edit, :update, :destroy, :availability, :update_availability]
  
  def index
    @staff_members = current_business_scope.staff_members.includes(:services)
                                         .order(active: :desc, name: :asc)
  end
  
  def show
    @upcoming_bookings = @staff_member.bookings.upcoming.includes(:service, :tenant_customer)
                                     .limit(10)
  end
  
  def new
    @staff_member = current_business_scope.staff_members.new
    @services = current_business_scope.services.active
  end
  
  def create
    @staff_member = current_business_scope.staff_members.new(staff_member_params)
    
    if @staff_member.save
      redirect_to @staff_member, notice: 'Staff member was successfully created.'
    else
      @services = current_business_scope.services.active
      render :new
    end
  end
  
  def edit
    @services = current_business_scope.services.active
  end
  
  def update
    if @staff_member.update(staff_member_params)
      redirect_to @staff_member, notice: 'Staff member was successfully updated.'
    else
      @services = current_business_scope.services.active
      render :edit
    end
  end
  
  def destroy
    if @staff_member.destroy
      redirect_to staff_index_path, notice: 'Staff member was successfully deleted.'
    else
      redirect_to @staff_member, alert: 'This staff member has associated bookings and cannot be deleted.'
    end
  end
  
  # GET /staff/:id/availability
  def availability
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @start_date = @date.beginning_of_week
    @end_date = @date.end_of_week
    
    # Get the calendar data for the entire week
    @calendar_data = AvailabilityService.availability_calendar(
      staff_member: @staff_member,
      start_date: @start_date,
      end_date: @end_date
    )
    
    # Get services this staff member can provide
    @services = @staff_member.services.active
  end
  
  # PATCH /staff/:id/update_availability
  def update_availability
    # Get the availability data from params
    availability_data = params.require(:staff_member).require(:availability).permit!.to_h
    
    # Update the staff member with the availability data
    if @staff_member.update(availability: availability_data)
      respond_to do |format|
        format.html { redirect_to availability_staff_path(@staff_member), notice: 'Availability was successfully updated.' }
        format.json { render json: { success: true, message: 'Availability was successfully updated.' }, status: :ok }
      end
    else
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
      
      @calendar_data = AvailabilityService.availability_calendar(
        staff_member: @staff_member,
        start_date: @start_date,
        end_date: @end_date
      )
      
      @services = @staff_member.services.active
      
      respond_to do |format|
        format.html { render :availability }
        format.json { render json: { success: false, errors: @staff_member.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end
  
  private
  
  def set_staff_member
    @staff_member = current_business_scope.staff_members.find(params[:id])
  end
  
  def staff_member_params
    params.require(:staff_member).permit(
      :name, :email, :phone, :bio, :active, :position, :photo_url,
      service_ids: []
    )
  end
  
  def current_business_scope
    ActsAsTenant.current_tenant || current_user&.business
  end
end
