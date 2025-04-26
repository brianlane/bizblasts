class StaffMembersController < ApplicationController
  before_action :set_staff_member, only: [:show, :edit, :update, :destroy, :manage_availability]
  before_action :authorize_non_client, only: [:index, :show, :new, :edit, :create, :update, :destroy, :manage_availability, :update_availability]
  
  def index
    @staff_members = current_business_scope.staff_members
  end
  
  def show
  end
  
  def new
    @staff_member = current_business_scope.staff_members.new
  end
  
  def edit
  end
  
  def create
    @staff_member = current_business_scope.staff_members.new(staff_member_params)
    
    if @staff_member.save
      redirect_to @staff_member, notice: 'Staff member was successfully created.'
    else
      render :new
    end
  end
  
  def update
    if @staff_member.update(staff_member_params)
      redirect_to @staff_member, notice: 'Staff member was successfully updated.'
    else
      render :edit
    end
  end
  
  def destroy
    if @staff_member.destroy
      redirect_to staff_members_path, notice: 'Staff member was successfully deleted.'
    else
      redirect_to @staff_member, alert: 'Unable to delete this staff member.'
    end
  end
  
  # GET /staff_members/:id/manage_availability
  def manage_availability
  end
  
  # PATCH /staff_members/:id/manage_availability
  def update_availability
    @staff_member = current_business_scope.staff_members.find(params[:id])
    
    # Process the availability data
    availability_data = params[:availability] || {}
    
    # Update the staff member's availability
    if @staff_member.update(availability: availability_data)
      respond_to do |format|
        format.html { redirect_to manage_availability_staff_member_path(@staff_member), notice: 'Availability was successfully updated.' }
        format.json { render json: { success: true, message: 'Availability was successfully updated.' } }
      end
    else
      respond_to do |format|
        format.html { render :manage_availability }
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
      :name, 
      :email, 
      :phone, 
      :bio, 
      :position, 
      :active,
      :photo_url,
      service_ids: []
    )
  end
  
  # Get the current business scope for multi-tenancy
  def current_business_scope
    ActsAsTenant.current_tenant || current_user&.business
  end
  
  def authorize_non_client
    if current_user && current_user.client?
      redirect_to dashboard_path, alert: "Clients cannot access staff information."
    end
  end
end 
 