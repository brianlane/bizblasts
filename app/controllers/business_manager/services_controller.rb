class BusinessManager::ServicesController < BusinessManager::BaseController
  # Ensure user is authenticated and acting within their current business context
  # BaseController handles authentication and setting @current_business

  before_action :set_service, only: [:show, :edit, :update, :destroy]

  # GET /business_manager/services
  def index
    # TODO: Add filtering/sorting later
    @services = @current_business.services.order(:name).page(params[:page]).per(10) # Basic pagination
    # authorize @services # Add Pundit authorization later
  end

  # GET /business_manager/services/1
  def show
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later
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
      redirect_to business_manager_services_path, notice: 'Service was successfully created.'
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

    if @service.update(service_params_without_images) && handle_image_updates
      redirect_to business_manager_services_path, notice: 'Service was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /business_manager/services/:id
  def destroy
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later

    if @service.destroy
      redirect_to business_manager_services_path, notice: 'Service was successfully deleted.'
    else
      # Handle potential deletion restriction (e.g., due to existing bookings)
      redirect_to business_manager_services_path, alert: @service.errors.full_messages.join(', ')
    end
  end

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
      :tips_enabled,
      :allow_discounts,
      :availability_settings,
      :service_type,
      :min_bookings,
      :max_bookings,
      :subscription_enabled, :subscription_discount_percentage, :subscription_billing_cycle, :subscription_rebooking_preference, :allow_customer_preferences,
      staff_member_ids: [], # Allow staff assignment via new association
      add_on_product_ids: [], # Allow add-on product assignment
      images: [], # Allow new image uploads
      images_attributes: [:id, :primary, :position, :_destroy] # Allow managing existing images
    )
  end

  def service_params_without_images
    service_params.except(:images)
  end

  def handle_image_updates
    new_images = params.dig(:service, :images)
    
    # If there are new images, append them to existing ones
    if new_images.present?
      # Filter out empty uploads
      valid_images = Array(new_images).compact.reject(&:blank?)
      
      if valid_images.any?
        @service.images.attach(valid_images)
        
        # Check for attachment errors
        if @service.images.any? { |img| !img.persisted? }
          @service.errors.add(:images, "Failed to attach some images")
          return false
        end
      end
    end
    
    return true
  rescue => e
    @service.errors.add(:images, "Error processing images: #{e.message}")
    return false
  end

end
