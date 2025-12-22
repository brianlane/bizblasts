# frozen_string_literal: true

module BusinessManager
  class BookingsController < BaseController
    before_action :authenticate_user!
    before_action :require_business_staff!
    before_action :set_booking, only: [:show, :edit, :update, :confirm, :cancel, :reschedule, :update_schedule, :refund, :fill_form, :submit_form]
    before_action :set_form_template_and_submission, only: [:fill_form, :submit_form]
    
    # GET /manage/bookings
    def index
      @bookings = current_business.bookings
                  .includes(:service, :staff_member, :tenant_customer)
                  .order(created_at: :desc)
                  
      @status_filter = params[:status]
      @bookings = @bookings.by_status(@status_filter) if @status_filter.present?
      
      @date_filter = params[:date] ? Date.parse(params[:date]) : nil
      @bookings = @bookings.on_date(@date_filter) if @date_filter.present?
    end
    
    # GET /manage/bookings/:id
    def show
    end
    
    # GET /manage/bookings/new
    def new
      @booking = current_business.bookings.new
      
      # Handle service selection and variant
      if params[:service_id].present?
        @service = current_business.services.find_by(id: params[:service_id])
        @booking.service = @service if @service
        
        # Handle service variant if provided
        if params[:service_variant_id].present? && @service
          @service_variant = @service.service_variants.find_by(id: params[:service_variant_id])
          @booking.service_variant = @service_variant if @service_variant
        end
      end
      
      # Pre-fill staff member if provided
      @booking.staff_member_id = params[:staff_member_id] if params[:staff_member_id].present?
      
      # Pre-fill customer if provided
      @booking.tenant_customer_id = params[:tenant_customer_id] if params[:tenant_customer_id].present?
      
      # Pre-fill date/time if provided via query params
      if params[:date].present? && params[:start_time].present?
        current_business.ensure_time_zone! if current_business.respond_to?(:ensure_time_zone!)
        dt = BookingManager.process_datetime_params(params[:date], params[:start_time], current_business&.time_zone || 'UTC')
        @booking.start_time = dt if dt
      end
    end
    
    # GET /manage/bookings/:id/edit
    def edit
      # Load all available products for this business that have variants
      # Only include service or mixed product types and products visible to customers
      @available_products = current_business.products.active.includes(:product_variants)
                                  .where(product_type: [:service, :mixed])
                                  .where.not(product_variants: { id: nil })
                                  .select(&:visible_to_customers?) # Filter out hidden products
                                  .sort_by(&:name)
    end
    
    # PATCH /manage/bookings/:id
    def update
      # Debug logging
      Rails.logger.debug("=" * 50)
      Rails.logger.debug("Booking update params: #{params.inspect}")
      Rails.logger.debug("=" * 50)
      
      # Process booking_product_add_ons and set price and total amount
      # This runs before the actual update to ensure all nested attributes have proper values
      if params[:booking][:booking_product_add_ons_attributes].present?
        Rails.logger.debug("Processing product add-ons: #{params[:booking][:booking_product_add_ons_attributes].inspect}")
        
        params[:booking][:booking_product_add_ons_attributes].each do |key, add_on_params|
          # Skip if marked for destruction or quantity is 0
          if add_on_params[:_destroy] == '1' || add_on_params[:quantity].to_i <= 0
            Rails.logger.debug("Skipping add-on #{key}: destroy=#{add_on_params[:_destroy]}, quantity=#{add_on_params[:quantity]}")
            next
          end
          
          # Set price if this is a new add-on (no ID) or being updated
          if add_on_params[:id].blank?
            # Find the product variant to get its price
            product_variant = ProductVariant.find_by(id: add_on_params[:product_variant_id])
            Rails.logger.debug("Found product variant: #{product_variant.inspect}")
            
            if product_variant
              # Create a temporary add-on to calculate prices
              temp_add_on = BookingProductAddOn.new(
                product_variant: product_variant,
                quantity: add_on_params[:quantity]
              )
              # Don't need to save, just need the price and total amount
              temp_add_on.send(:set_price_and_total)
              
              # Add these values to the parameters that will be used for update
              add_on_params[:price] = temp_add_on.price
              add_on_params[:total_amount] = temp_add_on.total_amount
              
              Rails.logger.debug("Set price: #{add_on_params[:price]}, total: #{add_on_params[:total_amount]}")
            else
              Rails.logger.error("Product variant not found: #{add_on_params[:product_variant_id]}")
            end
          end
        end
      else
        Rails.logger.debug("No product add-ons found in params")
      end
      
      # For debugging, let's try a manual approach to adding product add-ons
      if params[:booking][:booking_product_add_ons_attributes].present?
        # Get basic booking attributes
        @booking.notes = params[:booking][:notes] if params[:booking][:notes].present?
        
        # Process each add-on manually
        params[:booking][:booking_product_add_ons_attributes].each do |key, add_on_params|
          Rails.logger.debug("Processing add-on: #{key} => #{add_on_params.inspect}")
          
          next if add_on_params[:_destroy] == '1' || add_on_params[:quantity].to_i <= 0
          
          product_variant_id = add_on_params[:product_variant_id]
          quantity = add_on_params[:quantity].to_i
          
          # Skip if no product variant or quantity is invalid
          next if product_variant_id.blank? || quantity <= 0
          
          # Find or initialize the add-on
          add_on = if add_on_params[:id].present?
            @booking.booking_product_add_ons.find_by(id: add_on_params[:id])
          else
            @booking.booking_product_add_ons.new(product_variant_id: product_variant_id)
          end
          
          # Skip if product add-on wasn't found
          next if add_on.nil?
          
          # Set attributes
          add_on.quantity = quantity
          
          # Calculate price if not set
          if add_on.new_record? || add_on.price.nil?
            temp_add_on = BookingProductAddOn.new(
              product_variant_id: product_variant_id,
              quantity: quantity
            )
            temp_add_on.send(:set_price_and_total)
            
            add_on.price = temp_add_on.price
            add_on.total_amount = temp_add_on.total_amount
          end
          
          # Save the add-on
          add_on.save
          Rails.logger.debug("Saved add-on: #{add_on.inspect}")
        end
        
        # Update the booking status to reflect we saved it
        @booking.save
        flash[:notice] = "Booking was successfully updated."
        redirect_to business_manager_booking_path(@booking) and return
      end
      
      # Get permitted parameters first
      permitted_attrs = booking_params
      
      # Automatically adjust end_time when rescheduling via update
      if params[:booking][:start_time].present? && @booking.service&.duration.present?
        begin
          # Parse new start_time and set end_time based on service duration
          new_start = Time.zone.parse(params[:booking][:start_time])
          if new_start
            new_end = new_start + @booking.service.duration.minutes
            # Build a safe, mutable copy of permitted params
            permitted_attrs = booking_params.to_h
            permitted_attrs[:end_time] = new_end.to_s
          end
        rescue ArgumentError
          # Ignore parse errors and let validations handle invalid times
        end
      end
      
      result = @booking.update(permitted_attrs)
      Rails.logger.debug("Update result: #{result}")
      Rails.logger.debug("Booking errors: #{@booking.errors.full_messages}") unless result
      
      if result
        flash[:notice] = "Booking was successfully updated."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem updating the booking."
        
        # Reload available products for the form
        @available_products = current_business.products.active.includes(:product_variants)
                                  .where(product_type: [:service, :mixed])
                                  .where.not(product_variants: { id: nil })
                                  .select(&:visible_to_customers?) # Filter out hidden products
                                  .sort_by(&:name)
        
        render :edit
      end
    end
    
    # PATCH /manage/bookings/:id/confirm
    def confirm
      if @booking.status == 'confirmed'
        flash[:notice] = "This booking was already confirmed."
      elsif @booking.update(status: :confirmed)
        # Send status update notification (email + SMS)
        NotificationService.booking_status_update(@booking)
        flash[:notice] = "Booking has been confirmed."
      else
        flash[:alert] = "There was a problem confirming the booking."
      end
      
      redirect_to business_manager_booking_path(@booking)
    end
    
    # PATCH /manage/bookings/:id/cancel
    def cancel
      cancellation_reason = params[:cancellation_reason] || "Cancelled by business"
      
      if @booking.status == 'cancelled'
        flash[:notice] = "This booking was already cancelled."
      else
        success, error_message = BookingManager.cancel_booking(@booking, cancellation_reason, true, current_user: current_user)
        if success
          flash[:notice] = "Booking has been cancelled."
        else
          # Handle policy-based cancellation restrictions
          flash[:alert] = error_message || "There was a problem cancelling the booking."
        end
      end
      
      redirect_to business_manager_booking_path(@booking)
    end

    # PATCH /manage/bookings/:id/refund
    def refund
      unless @booking.refundable?
        flash[:alert] = "This booking is not eligible for a refund."
        return redirect_to business_manager_booking_path(@booking)
      end

      refund_failures = []
      @booking.invoice.payments.successful.where.not(status: :refunded).each do |payment|
        success = payment.initiate_refund(reason: 'booking_refund', user: current_user)
        refund_failures << payment.id unless success
      end

      if refund_failures.empty?
        flash[:notice] = 'Refund initiated successfully.'
        @booking.update(status: :cancelled) if @booking.status != 'cancelled'
      else
        flash[:alert] = "Refund failed for payments: #{refund_failures.join(', ')}"
      end

      redirect_to business_manager_booking_path(@booking)
    end
    
    # GET /manage/bookings/:id/reschedule
    def reschedule
      @staff_members = current_business.staff_members.active
      @start_date = Date.today
      @end_date = @start_date + 14.days
      
      # Get the staff member - either from params or the booking's assigned staff
      staff_member_id = params[:staff_member_id].present? ? params[:staff_member_id] : @booking.staff_member_id
      @current_staff = current_business.staff_members.find_by(id: staff_member_id) || @booking.staff_member
      
      # Fetch available slots for the booking's current date, staff, and service
      @date_to_check = params[:date].present? ? Date.parse(params[:date]) : @booking.start_time.to_date
      
      # Debug - make sure the staff member is assigned to this service
      Rails.logger.debug("Staff member: #{@current_staff.name} (ID: #{@current_staff.id})")
      Rails.logger.debug("Staff member services: #{@current_staff.services.pluck(:id, :name)}")
      Rails.logger.debug("Booking service: #{@booking.service.id} - #{@booking.service.name}")
      
      # Ensure the staff member has this service assigned (especially important for reschedule)
      # The original booking already validates this, so it's safe to ensure it here
      unless @current_staff.services.include?(@booking.service)
        Rails.logger.debug("IMPORTANT: Staff member does not have this service assigned, temporarily assigning it")
        @current_staff.services << @booking.service unless @current_staff.services.include?(@booking.service)
      end
      
      # Try getting slots using the service's duration as the interval
      @available_slots = AvailabilityService.available_slots(
        @current_staff, 
        @date_to_check, 
        @booking.service,
        interval: @booking.service.duration
      )
      
      # If no slots are found, generate slots directly from the staff member's availability
      # This ensures users can always reschedule regardless of conflicts
      if @available_slots.empty?
        Rails.logger.debug("No slots found using standard method, generating basic slots from staff availability")
        generate_slots_from_availability
      end
      
      Rails.logger.debug "Available slots for reschedule: #{@available_slots.map { |s| s[:start_time].strftime('%H:%M') }}"
    end
    
    # PATCH /manage/bookings/:id/update_schedule
    def update_schedule
      new_start_time = Time.zone.parse("#{params[:date]} #{params[:start_time]}")
      service_duration = @booking.service.duration
      new_end_time = new_start_time + service_duration.minutes
      
      if @booking.update(start_time: new_start_time, end_time: new_end_time)
        # Send notification about reschedule (email + SMS)
        NotificationService.booking_status_update(@booking)
        flash[:notice] = "Booking has been rescheduled."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem rescheduling the booking."
        render :reschedule
      end
    end
    
    # GET /manage/bookings/:id/fill_form
    # Render a job form for staff to fill out
    def fill_form
      # Template and submission are set by before_action
      # Set default values for new submissions
      if @submission.new_record?
        @submission.staff_member = current_user.staff_member
        @submission.status = :draft
        @submission.responses = {}
      elsif !@submission.editable?
        # Prevent editing of submitted or approved forms
        redirect_to business_manager_booking_path(@booking), alert: 'This form submission cannot be edited.'
        return
      end
    end
    
    # POST /manage/bookings/:id/submit_form
    # Save job form submission
    def submit_form
      # Template and submission are set by before_action
      # Prevent modifying non-editable submissions (submitted/approved)
      if @submission.persisted? && !@submission.editable?
        redirect_to business_manager_booking_path(@booking), alert: 'This form submission cannot be modified.'
        return
      end

      # Wrap in transaction to ensure atomicity of file uploads and save
      save_result = ActiveRecord::Base.transaction do
        # Update responses from form submission, handling file uploads separately
        # Start with existing responses to preserve photo references that weren't re-uploaded
        responses_hash = (@submission.responses || {}).dup

        if params[:responses].present?
          params[:responses].each do |field_id, value|
            if value.is_a?(ActionDispatch::Http::UploadedFile)
              # Handle file uploads by attaching to the submission with error handling
              begin
                blob = ActiveStorage::Blob.create_and_upload!(
                  io: value,
                  filename: value.original_filename,
                  content_type: value.content_type
                )
                @submission.photos.attach(blob)
                # Store a reference to the attachment using blob's signed_id for unique lookup
                responses_hash[field_id] = { 'type' => 'photo', 'attached' => true, 'filename' => value.original_filename, 'blob_signed_id' => blob.signed_id }
              rescue ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError => e
                @submission.errors.add(:base, "Failed to upload file: #{e.message}")
                raise ActiveRecord::Rollback
              end
            else
              responses_hash[field_id] = value
            end
          end
        end
        @submission.responses = responses_hash

        # Determine if we're saving as draft or submitting
        result = if params[:commit] == 'Save as Draft' || params[:save_draft].present?
          @submission.status = :draft
          @submission.save
        else
          # Use submit! method which properly validates required fields
          @submission.submit!(user: current_user)
        end

        # Trigger rollback if save/submit failed to prevent orphaned photo attachments
        raise ActiveRecord::Rollback unless result

        result
      end

      if save_result
        if @submission.submitted?
          redirect_to business_manager_booking_path(@booking), notice: 'Form submitted successfully.'
        else
          redirect_to business_manager_booking_path(@booking), notice: 'Draft saved.'
        end
      else
        flash.now[:alert] = @submission.errors.full_messages.join(', ')
        render :fill_form, status: :unprocessable_entity
      end
    end
    
    # GET /manage/available-slots
    # This action shows available booking slots for a specific staff member and service
    def available_slots
      @service = current_business.services.find_by(id: params[:service_id])
      @staff_member = current_business.staff_members.find_by(id: params[:staff_member_id])
      
      if @service.nil? || @staff_member.nil?
        flash[:alert] = "Service or staff member not found"
        redirect_to business_manager_dashboard_path
        return
      end
      
      @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
      
      # Fetch calendar data for the selected week
      @calendar_data = {}
      (@start_date..@end_date).each do |date|
        @calendar_data[date.to_s] = AvailabilityService.available_slots(
          @staff_member,
          date,
          @service
        )
      end
    end
    
    # POST /manage/bookings
    def create
      @booking = current_business.bookings.new(booking_params)

      # Set foreign keys explicitly before calculating times
      @booking.service_id = params[:booking][:service_id] if params[:booking][:service_id].present?
      @booking.staff_member_id = params[:booking][:staff_member_id] if params[:booking][:staff_member_id].present?
      @booking.tenant_customer_id = params[:booking][:tenant_customer_id] if params[:booking][:tenant_customer_id].present?

      # Set start_time and end_time from date, time, and duration params if present
      date = params[:booking][:date]
      time = params[:booking][:time]
      duration = params[:booking][:duration].presence || @booking.service&.duration
      if date.present? && time.present? && duration.present?
        start_time = Time.zone.parse("#{date} #{time}")
        @booking.start_time = start_time
        @booking.end_time = start_time + duration.to_i.minutes
      end

      # Enforce booking policy validations
      policy = current_business.booking_policy

      # Max advance days policy
      if policy.max_advance_days.present? && (@booking.start_time.to_date - Date.current).to_i > policy.max_advance_days
        @booking.errors.add(:base, "Booking cannot be more than #{policy.max_advance_days} days in advance")
      end

      # Max daily bookings policy
      if policy.max_daily_bookings.present? && @booking.staff_member_id.present?
        day = @booking.start_time.to_date
        existing_count = current_business.bookings.where(staff_member_id: @booking.staff_member_id, start_time: day.all_day).count
        if existing_count >= policy.max_daily_bookings
          @booking.errors.add(:base, "Maximum daily bookings (#{policy.max_daily_bookings}) reached for this staff member")
        end
      end

      # Buffer time policy
      if policy.buffer_time_mins.present? && @booking.staff_member_id.present? && @booking.start_time.present?
        duration_mins = duration.to_i
        @booking.end_time ||= @booking.start_time + duration_mins.minutes if duration_mins.positive?

        if @booking.end_time.present?
          buffer = policy.buffer_time_mins.minutes
          buffer_window_start = @booking.start_time - buffer
          buffer_window_end = @booking.end_time + buffer

          conflict = current_business.bookings
            .where(staff_member_id: @booking.staff_member_id)
            .where.not(id: @booking.id)
            .where.not(status: :cancelled)
            .where("start_time < ? AND end_time > ?", buffer_window_end, buffer_window_start)
            .exists?

          if conflict
            @booking.errors.add(:base, "Requested booking conflicts with another existing booking due to buffer time policy")
          end
        end
      end

      # Duration constraints policy
      if policy.min_duration_mins.present? && duration.to_i < policy.min_duration_mins
        @booking.errors.add(:base, "Booking cannot be less than the minimum required duration")
      end

      if policy.max_duration_mins.present? && duration.to_i > policy.max_duration_mins
        @booking.errors.add(:base, "Booking cannot exceed the maximum allowed duration")
      end

      # Render form with errors if any policy violations
      if @booking.errors.any?
        flash.now[:alert] = @booking.errors.full_messages.join(', ')
        return render :new, status: :unprocessable_content
      end

      if @booking.save
        flash[:notice] = "Booking was successfully created."
        redirect_to business_manager_booking_path(@booking)
      else
        #raise "DEBUG: Booking errors: #{@booking.errors.full_messages.inspect}"
        flash.now[:alert] = @booking.errors.full_messages.join(', ')
        render :new, status: :unprocessable_content
      end
    end
    
    private
    
    # Helper method to ensure user is staff or manager
    def require_business_staff!
      unless current_user && (current_user.manager? || current_user.staff?)
        flash[:alert] = "You need to be a staff member or manager to access this area."
        redirect_to root_path
      end
    end
    
    def set_booking
      @booking = current_business.bookings.includes(
                   :service, 
                   :staff_member, 
                   :tenant_customer, 
                   :business,
                   booking_product_add_ons: { product_variant: :product }
                 ).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = "Booking not found."
      redirect_to business_manager_bookings_path
    end
    
    def booking_params
      # For complex nested attributes like this, we need to build the permitted parameters
      # differently to handle dynamic keys
      params.require(:booking).permit(
        :service_id, :service_variant_id, :staff_member_id, :tenant_customer_id,
        :start_time, :end_time, :status, :notes,
        :amount, :original_amount, :discount_amount, # Allow setting amounts manually if needed
        :cancellation_reason,
        :quantity, # Permit quantity
        # Nested attributes for product add-ons
        booking_product_add_ons_attributes: [
          :id, :product_variant_id, :quantity, :_destroy
        ]
      )
    end
    
    # Helper method to generate time slots from basic staff availability
    def generate_slots_from_availability
      staff_member = @current_staff
      date = @date_to_check
      service = @booking.service
      
      # Get the day's availability intervals from staff member's schedule
      day_name = date.strftime('%A').downcase
      availability_data = staff_member.availability&.with_indifferent_access || {}
      
      # Check for date-specific exceptions first, then fall back to regular schedule
      intervals = if availability_data[:exceptions]&.key?(date.iso8601)
        availability_data[:exceptions][date.iso8601]
      else
        availability_data[day_name]
      end
      
      return if intervals.blank?
      
      # Generate slots every hour between the start and end times
      @available_slots = []
      
      intervals.each do |interval_data|
        start_time_str = interval_data['start']
        end_time_str = interval_data['end']
        
        next unless start_time_str && end_time_str
        
        # Parse the time strings into Time objects for the given date
        begin
          start_hour, start_minute = start_time_str.split(':').map(&:to_i)
          end_hour, end_minute = end_time_str.split(':').map(&:to_i)
          
          # Create times in the business's time zone
          interval_start = Time.zone.local(date.year, date.month, date.day, start_hour, start_minute)
          interval_end = Time.zone.local(date.year, date.month, date.day, end_hour, end_minute)
          
          # Generate a slot every hour (or service duration)
          step = 60.minutes
          current_time = interval_start
          
          # Only include times that allow the full service duration to fit
          while current_time + service.duration.minutes <= interval_end
            @available_slots << {
              start_time: current_time,
              end_time: current_time + service.duration.minutes
            }
            current_time += step
          end
        rescue ArgumentError => e
          Rails.logger.error("Invalid time format in staff availability: #{e.message}")
          next
        end
      end
    end

    # Set the form template and submission for fill_form and submit_form actions
    def set_form_template_and_submission
      @template = current_business.job_form_templates.find(params[:template_id])

      # Find or create a submission for this booking and template
      @submission = if params[:submission_id].present?
        submission = @booking.job_form_submissions.find(params[:submission_id])
        # Verify the submission belongs to the requested template
        if submission.job_form_template_id != @template.id
          redirect_to business_manager_booking_path(@booking), alert: 'Form template mismatch.'
          return
        end
        submission
      else
        # Use find_or_initialize_by for both actions to prevent duplicate submissions
        submission = @booking.job_form_submissions.find_or_initialize_by(
          job_form_template: @template,
          business: current_business
        )
        # Set staff_member if this is a new record
        submission.staff_member ||= current_user.staff_member
        submission
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to business_manager_booking_path(@booking), alert: 'Form template or submission not found.'
      return
    end
  end
end 