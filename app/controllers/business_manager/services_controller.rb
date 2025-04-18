class BusinessManager::ServicesController < BusinessManager::BaseController
  # Ensure user is authenticated and acting within their current business context
  # BaseController likely handles authentication and setting @current_business

  before_action :set_service, only: [:edit, :update, :destroy]
  # Note: Removed :show from before_action

  # GET /business_manager/services
  def index
    # TODO: Add filtering/sorting later
    @services = @current_business.services.order(created_at: :desc).page(params[:page]).per(10) # Basic pagination
    authorize @services # Add Pundit authorization later
  end

  # GET /business_manager/services/new
  def new
    @service = @current_business.services.new
    # authorize @service
  end

  # POST /business_manager/services
  def create
    @service = @current_business.services.new(service_params)
    # authorize @service # Add Pundit authorization later

    if @service.save
      # Handle staff assignments - update assigned_staff based on user_ids param
      update_staff_assignments
      redirect_to "/services", notice: 'Service was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /business_manager/services/:id/edit
  def edit
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later
  end

  # PATCH/PUT /business_manager/services/:id
  def update
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later

    if @service.update(service_params)
      # Handle staff assignments - update assigned_staff based on user_ids param
      update_staff_assignments
      redirect_to "/services", notice: 'Service was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /business_manager/services/:id
  def destroy
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later

    if @service.destroy
      redirect_to "/services", notice: 'Service was successfully deleted.'
    else
      # Handle potential deletion restriction (e.g., due to existing bookings)
      redirect_to "/services", alert: @service.errors.full_messages.join(', ')
    end
  end

  # Removed show action
  # def show
  # end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_service
    @service = @current_business.services.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_services_path, alert: 'Service not found.'
  end

  # Only allow a list of trusted parameters through.
  def service_params
    params.require(:service).permit(
      :name,
      :description,
      :price,
      :duration,
      :featured,
      :active,
      :availability_settings,
      # user_ids: [] # Removed: Let update_staff_assignments handle this
    )
  end

  # Helper method to update staff assignments based on submitted user_ids
  def update_staff_assignments
    # Ensure user_ids parameter exists and is an array before proceeding
    submitted_user_ids = params.dig(:service, :user_ids)&.reject(&:blank?)&.map(&:to_i) || []

    # Get the users belonging to the current business to ensure we only assign valid staff
    valid_users = @current_business.users.where(id: submitted_user_ids)

    # Update the service's assigned staff
    @service.assigned_staff = valid_users
  end

end
