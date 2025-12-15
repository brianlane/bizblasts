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
    # Prepare an empty nested user so fields_for :user will yield
    @staff_member.build_user
    # authorize @staff_member # Add Pundit authorization later
  end

  # GET /business_manager/staff_members/1/edit
  def edit
    # @staff_member is set by before_action
    # Populate the virtual user_role so the dropdown shows the current role
    @staff_member.user_role = @staff_member.user&.role if @staff_member.user.present?
    # authorize @staff_member # Add Pundit authorization later
  end

  # POST /business_manager/staff_members
  def create
    # Always build a new staff User
    user_attrs  = staff_member_params[:user_attributes] || {}
    user_role   = staff_member_params[:user_role] || 'staff'
    @user = User.new(user_attrs.merge(role: user_role, business_id: @current_business.id))
    if @user.save
      # Bypass Devise confirmation and send reset password instructions
      @user.send_reset_password_instructions
    else
      # On user validation failure, rebuild staff_member and nested user for form
      @staff_member = @current_business.staff_members.new(staff_member_params.except(:user_attributes))
      @staff_member.build_user(user_attrs)
      @staff_member.errors.add(:user, @user.errors.full_messages.to_sentence)
      render :new, status: :unprocessable_content and return
    end

    # Now build the StaffMember record linking the new user
    @staff_member = @current_business.staff_members.new(staff_member_params.except(:user_attributes))
    @staff_member.user = @user

    if @staff_member.save
      redirect_to business_manager_staff_member_path(@staff_member), notice: 'Staff member was successfully created.'
    else
      # Preserve nested user data on failure so form can re-render the new-user fields
      @staff_member.build_user(user_attrs)
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /business_manager/staff_members/1
  def update
    # @staff_member is set by before_action
    # authorize @staff_member # Add Pundit authorization later

    # Filter out blank password fields to prevent unnecessary validation
    update_params = staff_member_params
    if update_params[:user_attributes].present?
      user_attrs = update_params[:user_attributes]
      # Remove password fields if they're blank (user doesn't want to change password)
      if user_attrs[:password].blank? && user_attrs[:password_confirmation].blank?
        user_attrs.delete(:password)
        user_attrs.delete(:password_confirmation)
      end
    end

    if @staff_member.update(update_params)
      redirect_to business_manager_staff_member_path(@staff_member), notice: 'Staff member was successfully updated.'
    else
      render :edit, status: :unprocessable_content
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
    # Set date context for form and exceptions
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @start_date = @date.beginning_of_week
    @end_date = @date.end_of_week
    
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
      # Build day names dynamically starting from the calendar's start_date to
      # ensure we match the configured beginning_of_week (Sunday vs Monday).
      days_of_week = (0..6).map { |d| (@start_date + d.days).strftime('%A').downcase }
      
      days_of_week.each do |day|
        full_day_param = params.dig(:full_day, day)

        # Full-day checkbox returns '1' when checked
        if full_day_param == '1'
          availability_data[day] = [{ 'start' => '00:00', 'end' => '23:59' }]
          Rails.logger.debug "#{day.capitalize} set to full 24-hour availability"
        else
          day_params = availability_params[day]
          
          if day_params.is_a?(Hash) && day_params.any?
            slots = day_params.values.map do |slot_data|
              { 'start' => slot_data['start'], 'end' => slot_data['end'] } if slot_data['start'].present? && slot_data['end'].present?
            end.compact
            
            availability_data[day] = slots
            Rails.logger.info "Day #{day} slots: #{slots.inspect}"
          else
            # If no slots are submitted for a day (and it's not a full day), ensure it's saved as an empty array
            availability_data[day] = []
          end
        end
      end
      
      # Log the final data we're about to save
      Rails.logger.info "Saving availability data: #{availability_data.inspect}"
      
      # Compute final availability based on only_current_week flag
      final_availability = if params.dig(:staff_member, :only_current_week) == '1'
        old_avail = @staff_member.availability || {}
        exceptions = old_avail['exceptions'] || {}

        # Map each day-of-week to the corresponding date in the current week
        days_of_week.each_with_index do |day, idx|
          date_key = (@start_date + idx.days).iso8601
          exceptions[date_key] = availability_data[day]
        end

        old_avail.merge('exceptions' => exceptions)
      else
        availability_data
      end
      
      # Update staff_member availability
      if @staff_member.update(availability: final_availability)
        Rails.logger.info "Successfully saved availability: #{@staff_member.reload.availability.inspect}"
        flash[:notice] = if params.dig(:staff_member, :only_current_week) == '1'
          "#{@staff_member.name}'s availability for this week was successfully updated."
        else
          "#{@staff_member.name}'s availability was successfully updated."
        end
        redirect_to manage_availability_business_manager_staff_member_path(@staff_member, date: @date, bust_cache: true)
      else
        # Create user-friendly error message for overnight shifts
        error_messages = @staff_member.errors.full_messages
        user_friendly_errors = error_messages.map do |msg|
          if msg.include?("Shifts are not supported")
            # Extract the day name from the error message
            day_match = msg.match(/on '(\w+)'/)
            day_name = day_match ? day_match[1].capitalize : "a day"
            "#{day_name}: Shifts are not supported. Please use the 'Full 24 Hour Availability' checkbox or create separate time slots for each day."
          else
            msg
          end
        end
        
        error_message = user_friendly_errors.join('. ')
        Rails.logger.error "Failed to save availability: #{@staff_member.errors.full_messages.join(', ')}"
        
        # Set flash message and add debug logging
        flash.now[:alert] = error_message
        Rails.logger.debug "Flash alert set to: #{flash.now[:alert]}"
        
        @calendar_data = AvailabilityService.availability_calendar(
          staff_member: @staff_member,
          start_date: @start_date,
          end_date: @end_date,
          bust_cache: true
        )
        
        @services = @staff_member.services.active
        render 'business_manager/staff_members/availability', status: :unprocessable_content
      end
    else
      # GET request
      # @date, @start_date, and @end_date are already set above
      
      bust_cache = params[:bust_cache] == 'true'
      
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
        end_date: @end_date,
        bust_cache: bust_cache
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
      :name,
      :email,
      :phone,
      :position,
      :photo,
      :active,
      :bio,
      :notes,
      :adp_employee_id,
      :adp_pay_code,
      :adp_department_code,
      :adp_job_code,
      :user_role,
      service_ids: [],
      user_attributes: [:id, :first_name, :last_name, :email, :password, :password_confirmation]
    )
  end

  # Helper to permit dynamic keys (slot indices) mapping to start/end times
  def permit_dynamic_slots
    # Allows any key (e.g., "0", "1") to contain a hash with "start" and "end"
    Hash.new { |h, k| h[k] = [:start, :end] }
  end
end 