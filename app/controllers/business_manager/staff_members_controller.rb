class BusinessManager::StaffMembersController < BusinessManager::BaseController
  # Ensure user is authenticated and acting within their current business context
  # BaseController handles authentication and setting @current_business

  before_action :set_staff_member, only: [:show, :edit, :update, :destroy, :manage_availability]

  # GET /business_manager/staff_members
  def index
    @staff_members = @current_business.staff_members.includes(:user).order('LOWER(name)').page(params[:page]).per(10)
    # authorize @staff_members # Add Pundit authorization later
  end

  # GET /business_manager/staff_members/1
  def show
    # @staff_member is set by before_action
    # authorize @staff_member # Add Pundit authorization later
  end

  # GET /business_manager/staff_members/new
  def new
    @staff_member = @current_business.staff_members.new
    # authorize @staff_member # Add Pundit authorization later
  end

  # GET /business_manager/staff_members/1/edit
  def edit
    # @staff_member is set by before_action
    # authorize @staff_member # Add Pundit authorization later
  end

  # POST /business_manager/staff_members
  def create
    @staff_member = @current_business.staff_members.new(staff_member_params)
    # authorize @staff_member # Add Pundit authorization later

    if @staff_member.save
      redirect_to business_manager_staff_member_path(@staff_member), notice: 'Staff member was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /business_manager/staff_members/1
  def update
    # @staff_member is set by before_action
    # authorize @staff_member # Add Pundit authorization later

    if @staff_member.update(staff_member_params)
      redirect_to business_manager_staff_member_path(@staff_member), notice: 'Staff member was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /business_manager/staff_members/1
  def destroy
    # @staff_member is set by before_action
    # authorize @staff_member # Add Pundit authorization later

    if @staff_member.destroy
      redirect_to business_manager_staff_members_path, notice: 'Staff member was successfully removed.'
    else
      redirect_to business_manager_staff_members_path, alert: @staff_member.errors.full_messages.join(', ')
    end
  end
  
  # GET/PATCH /business_manager/staff_members/1/manage_availability
  def manage_availability
    # @staff_member is set by before_action
    
    if request.patch?
      # Handle updating availability
      # Initialize availability data structure
      availability_data = {
        'monday' => [],
        'tuesday' => [],
        'wednesday' => [],
        'thursday' => [],
        'friday' => [],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
      
      # Permit the expected nested structure from the form
      availability_params = params.require(:staff_member).require(:availability).permit(
        monday: permit_dynamic_slots,
        tuesday: permit_dynamic_slots,
        wednesday: permit_dynamic_slots,
        thursday: permit_dynamic_slots,
        friday: permit_dynamic_slots,
        saturday: permit_dynamic_slots,
        sunday: permit_dynamic_slots,
        exceptions: {}
      ).to_h
      Rails.logger.info "Permitted availability params: #{availability_params.inspect}"
      
      # Extract availability parameters
      days_of_week = %w[monday tuesday wednesday thursday friday saturday sunday]
      
      days_of_week.each do |day|
        # Get all parameters for this day
        day_params = availability_params[day]
        
        Rails.logger.debug "Raw #{day} params: #{day_params.inspect}"
        
        next unless day_params.is_a?(Hash) && day_params.any?
        
        # Process each slot for this day
        slots = []
        day_params.each do |slot_index, slot_data|
          next unless slot_data.is_a?(Hash)
          
          # Extract start and end times - using string keys since we're working with a hash now
          start_time = slot_data["start"]
          end_time = slot_data["end"]
          
          # Only add the slot if both times are present
          if start_time.present? && end_time.present?
            slots << {
              'start' => start_time,
              'end' => end_time
            }
            Rails.logger.debug "Added slot: start=#{start_time}, end=#{end_time}"
          end
        end
        
        # Add the slots to the availability data
        availability_data[day] = slots
        
        # Log for debugging
        Rails.logger.info "Day #{day} slots: #{availability_data[day].inspect}"
      end
      
      # Log the final data we're about to save
      Rails.logger.info "Saving availability data: #{availability_data.inspect}"
      
      # Update the staff member with the processed availability data
      if @staff_member.update(availability: availability_data)
        # Log the saved data for debugging
        Rails.logger.info "Successfully saved availability: #{@staff_member.reload.availability.inspect}"
        flash[:notice] = "#{@staff_member.name}'s availability was successfully updated."
        redirect_to manage_availability_business_manager_staff_member_path(@staff_member)
      else
        error_message = "Failed to save availability: #{@staff_member.errors.full_messages.join(', ')}"
        Rails.logger.error error_message
        flash.now[:alert] = error_message
        
        @date = params[:date] ? Date.parse(params[:date]) : Date.today
        @start_date = @date.beginning_of_week
        @end_date = @date.end_of_week
        
        @calendar_data = AvailabilityService.availability_calendar(
          staff_member: @staff_member,
          start_date: @start_date,
          end_date: @end_date
        )
        
        @services = @staff_member.services.active
        render 'business_manager/staff_members/availability'
      end
    else
      # GET request
      @date = params[:date] ? Date.parse(params[:date]) : Date.today
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
      
      # Ensure staff member has a properly initialized availability hash
      if @staff_member.availability.blank? || !@staff_member.availability.is_a?(Hash)
        @staff_member.availability = {
          'monday' => [],
          'tuesday' => [],
          'wednesday' => [],
          'thursday' => [],
          'friday' => [],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        }
        # Save the initialized structure
        @staff_member.save(validate: false)
      end
      
      # Get the calendar data for the entire week
      @calendar_data = AvailabilityService.availability_calendar(
        staff_member: @staff_member,
        start_date: @start_date,
        end_date: @end_date
      )
      
      # Get services this staff member can provide
      @services = @staff_member.services.active
      
      render 'business_manager/staff_members/availability'
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_staff_member
    @staff_member = @current_business.staff_members.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_staff_members_path, alert: 'Staff member not found.'
  end

  # Only allow a list of trusted parameters through.
  def staff_member_params
    params.require(:staff_member).permit(
      :user_id,
      :name,
      :email,
      :phone,
      :position,
      :photo_url,
      :active,
      :bio,
      :notes,
      service_ids: []
    )
  end

  # Helper to permit dynamic keys (slot indices) mapping to start/end times
  def permit_dynamic_slots
    # Allows any key (e.g., "0", "1") to contain a hash with "start" and "end"
    Hash.new { |h, k| h[k] = [:start, :end] }
  end
end 