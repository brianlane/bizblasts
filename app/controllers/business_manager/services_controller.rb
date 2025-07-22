class BusinessManager::ServicesController < BusinessManager::BaseController
  # Ensure user is authenticated and acting within their current business context
  # BaseController handles authentication and setting @current_business

  before_action :set_service, only: [:show, :edit, :update, :destroy, :update_position, :move_up, :move_down, :manage_availability]

  # GET /business_manager/services
  def index
    @services = current_business.services.positioned.includes(:staff_members, images_attachments: :blob)
    
    # Apply pagination if using kaminari
    @services = @services.page(params[:page]) if @services.respond_to?(:page)
    # authorize @services # Add Pundit authorization later
  end

  # GET /business_manager/services/1
  def show
    # @service is set by before_action
    # authorize @service # Add Pundit authorization later
  end

  # GET /business_manager/services/new
  def new
    @service = current_business.services.new
    # authorize @service
  end

  # POST /business_manager/services
  def create
    @service = current_business.services.new(service_params_without_availability)
    # authorize @service # Add Pundit authorization later

    if @service.save
      # Process availability data if provided
      if availability_data_present?
        process_availability_data(@service)
      end
      
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

    # Check if this is a "Use Default" action (clearing availability) before processing
    is_clearing_availability = clearing_availability?
    
    if @service.update(service_params_without_images_and_availability) && handle_image_updates
      # Process availability data if provided and not clearing
      if availability_data_present? && !is_clearing_availability
        process_availability_data(@service)
      elsif is_clearing_availability
        # Clear availability when using default
        process_clear_availability_data(@service)
      end
      
      # Redirect based on whether we're clearing availability
      if is_clearing_availability
        if request.referer&.include?('edit')
          redirect_to edit_business_manager_service_path(@service), 
                      notice: 'Service availability has been cleared. Using staff availability only.'
        else
          redirect_to business_manager_services_path, notice: 'Service was successfully updated.'
        end
      else
        redirect_to business_manager_services_path, notice: 'Service was successfully updated.'
      end
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

      def update_position
      new_position = params[:position].to_i
      
      if @service.move_to_position(new_position)
        render json: { status: 'success', message: 'Service position updated successfully' }
      else
        render json: { status: 'error', message: 'Failed to update service position' }, status: :unprocessable_entity
      end
    end

    def move_up
      # Check if service is already at the top
      services_list = current_business.services.positioned.to_a
      current_index = services_list.index(@service)
      
      if current_index.nil?
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Service not found' }, status: :not_found }
          format.html { redirect_to business_manager_services_path, alert: 'Service not found' }
        end
        return
      end
      
      if current_index == 0
        # Already at the top, do nothing but return success
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Service is already at the top' } }
          format.html { redirect_to business_manager_services_path, notice: 'Service is already at the top' }
        end
        return
      end
      
      # Move to previous position
      target_service = services_list[current_index - 1]
      if @service.move_to_position(target_service.position)
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Service moved up successfully' } }
          format.html { redirect_to business_manager_services_path, notice: 'Service moved up successfully' }
        end
      else
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Failed to move service up' }, status: :unprocessable_entity }
          format.html { redirect_to business_manager_services_path, alert: 'Failed to move service up' }
        end
      end
    end

    def move_down
      # Check if service is already at the bottom
      services_list = current_business.services.positioned.to_a
      current_index = services_list.index(@service)
      
      if current_index.nil?
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Service not found' }, status: :not_found }
          format.html { redirect_to business_manager_services_path, alert: 'Service not found' }
        end
        return
      end
      
      if current_index == services_list.length - 1
        # Already at the bottom, do nothing but return success
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Service is already at the bottom' } }
          format.html { redirect_to business_manager_services_path, notice: 'Service is already at the bottom' }
        end
        return
      end
      
      # Move to next position
      target_service = services_list[current_index + 1]
      if @service.move_to_position(target_service.position)
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Service moved down successfully' } }
          format.html { redirect_to business_manager_services_path, notice: 'Service moved down successfully' }
        end
      else
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Failed to move service down' }, status: :unprocessable_entity }
          format.html { redirect_to business_manager_services_path, alert: 'Failed to move service down' }
        end
      end
    end

    # Manage service-specific availability schedule
    def manage_availability
      @availability_manager = ServiceAvailabilityManager.new(
        service: @service,
        date: params[:date],
        logger: logger
      )
      
      date_info = @availability_manager.date_info
      @date = date_info[:current_date]
      @start_date = date_info[:start_date]
      @end_date = date_info[:end_date]
      
      if request.patch?
        handle_availability_update
      else
        handle_availability_display
      end
    end

  private

  # Check if this request is clearing availability (Use Default button)
  def clearing_availability?
    service_params = params[:service] || {}
    
    # Use string keys since Rails params use strings
    return false unless service_params.key?('enforce_service_availability')
    
    # Check if enforcement is being disabled (main indicator of Use Default)
    enforcement_disabled = service_params['enforce_service_availability'] == 'false' || service_params['enforce_service_availability'] == false
    
    # If availability is provided, it should be empty. If not provided, assume clearing.
    if service_params.key?('availability')
      availability_empty = service_params['availability'].blank? || service_params['availability'] == {}
      availability_empty && enforcement_disabled
    else
      # No availability key means we're not processing availability, check if just disabling enforcement
      enforcement_disabled
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_service
    @service = current_business.services.find(params[:id])
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
      :service_type,
      :min_bookings,
      :max_bookings,
      :subscription_enabled,
      :subscription_discount_percentage,
      :subscription_billing_cycle,
      :subscription_rebooking_preference,
      :allow_customer_preferences,
      :allow_discounts,
      :position, # Allow position updates
      :enforce_service_availability, # Allow enforcement setting
      staff_member_ids: [], # Allow staff assignment via new association
      add_on_product_ids: [], # Allow add-on product assignment
      images: [], # Allow new image uploads
      images_attributes: [:id, :primary, :position, :_destroy],
      service_variants_attributes: [:id, :name, :duration, :price, :active, :position, :_destroy],
      availability: {}
    )
  end

  def service_params_without_images
    service_params.except(:images)
  end

  def service_params_without_availability
    service_params.except(:availability)
  end

  def service_params_without_images_and_availability
    service_params.except(:images, :availability)
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

  # Helper to permit dynamic slot hashes
  def permit_dynamic_slots
    Hash.new { |h,k| h[k]=[:start,:end] }
  end

  # Handle availability update (PATCH request)
  def handle_availability_update
    service_params = params.require(:service)
    availability_params = service_params.fetch(:availability, {}).permit(
      monday: permit_dynamic_slots,
      tuesday: permit_dynamic_slots,
      wednesday: permit_dynamic_slots,
      thursday: permit_dynamic_slots,
      friday: permit_dynamic_slots,
      saturday: permit_dynamic_slots,
      sunday: permit_dynamic_slots,
      exceptions: {}
    ).to_h

    full_day_params = params.fetch(:full_day, {})
    
    # Update enforcement setting if provided
    if service_params[:enforce_service_availability].present?
      @availability_manager.update_enforcement(service_params[:enforce_service_availability])
    end

    success = @availability_manager.update_availability(availability_params, full_day_params)

    if success
      redirect_to business_manager_services_path, 
                  notice: "Availability settings for \"#{@service.name}\" were successfully updated."
    else
      logger.error("Failed to update service availability: #{@availability_manager.errors}")
      @calendar_data = @availability_manager.generate_calendar_data(bust_cache: true)
      
      flash.now[:alert] = @availability_manager.errors.any? ? 
        @availability_manager.errors.join(', ') : 
        'Failed to update availability settings. Please check your input and try again.'
      
      render 'availability', status: :unprocessable_entity
    end
  rescue => e
    logger.error("Exception in availability update: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    redirect_to business_manager_services_path, 
                alert: 'An unexpected error occurred while updating availability settings.'
  end

  # Handle availability display (GET request)
  def handle_availability_display
    bust_cache = params[:bust_cache] == 'true'
    @calendar_data = @availability_manager.generate_calendar_data(bust_cache: bust_cache)
    
    if @availability_manager.errors.any?
      logger.warn("Errors generating calendar data: #{@availability_manager.errors}")
      flash.now[:notice] = 'Some preview data could not be loaded. The form is still functional.'
    end
    
    render 'availability'
  rescue => e
    logger.error("Exception in availability display: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    redirect_to business_manager_services_path, 
                alert: 'Unable to load availability settings at this time.'
  end

  # Check if availability data is present in params
  def availability_data_present?
    params[:service].present? && (
      params[:service][:availability].present? || 
      params[:full_day].present? ||
      params[:enforce_service_availability].present?
    )
  end

  # Process clearing availability data (Use Default action)
  def process_clear_availability_data(service)
    availability_manager = ServiceAvailabilityManager.new(
      service: service,
      logger: logger
    )

    # Clear availability and disable enforcement 
    availability_manager.update_availability({})
    availability_manager.update_enforcement(false)
    
    # Also update the service directly to ensure enforcement is disabled
    service.update_column(:enforce_service_availability, false)
    
    Rails.logger.info("Cleared availability for service #{service.id} - using staff availability only")
  end

  # Process availability data using ServiceAvailabilityManager
  def process_availability_data(service)
    availability_manager = ServiceAvailabilityManager.new(
      service: service,
      logger: logger
    )

    availability_params = params[:service][:availability] || {}
    full_day_params = params[:full_day] || {}
    
    # Update enforcement setting if provided
    if params[:enforce_service_availability].present?
      availability_manager.update_enforcement(params[:enforce_service_availability])
    end

    # Update availability if data provided
    if availability_params.present? || full_day_params.present?
      success = availability_manager.update_availability(availability_params, full_day_params)
      
      unless success
        logger.warn("Failed to update availability during service save: #{availability_manager.errors}")
        # Don't fail the whole service save, but log the issue
        flash[:notice] = "Service saved successfully, but there were issues with availability settings."
      end
    end
  rescue => e
    logger.error("Exception processing availability data: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    # Don't fail the whole service save
    flash[:notice] = "Service saved successfully, but availability settings could not be processed."
  end

end
