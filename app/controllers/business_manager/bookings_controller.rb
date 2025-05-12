# frozen_string_literal: true

module BusinessManager
  class BookingsController < BaseController
    before_action :authenticate_user!
    before_action :require_business_staff!
    before_action :set_booking, only: [:show, :edit, :update, :confirm, :cancel, :reschedule, :update_schedule]
    
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
    
    # GET /manage/bookings/:id/edit
    def edit
      # Load all available products for this business that have variants
      @available_products = current_business.products.active.includes(:product_variants)
                                  .where.not(product_variants: { id: nil })
                                  .order(:name)
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
      
      result = @booking.update(booking_params)
      Rails.logger.debug("Update result: #{result}")
      Rails.logger.debug("Booking errors: #{@booking.errors.full_messages}") unless result
      
      if result
        flash[:notice] = "Booking was successfully updated."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem updating the booking."
        
        # Reload available products for the form
        @available_products = current_business.products.active.includes(:product_variants)
                                  .where.not(product_variants: { id: nil })
                                  .order(:name)
        
        render :edit
      end
    end
    
    # PATCH /manage/bookings/:id/confirm
    def confirm
      if @booking.status == 'confirmed'
        flash[:notice] = "This booking was already confirmed."
      elsif @booking.update(status: :confirmed)
        # Send email notification
        BookingMailer.status_update(@booking).deliver_later
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
      elsif BookingManager.cancel_booking(@booking, cancellation_reason)
        flash[:notice] = "Booking has been cancelled."
      else
        # Handle policy-based cancellation restrictions
        if @booking.errors[:base].any?
          flash[:alert] = @booking.errors[:base].first
        else
          flash[:alert] = "There was a problem cancelling the booking."
        end
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
        # Send email notification about reschedule
        BookingMailer.status_update(@booking).deliver_later
        flash[:notice] = "Booking has been rescheduled."
        redirect_to business_manager_booking_path(@booking)
      else
        flash.now[:alert] = "There was a problem rescheduling the booking."
        render :reschedule
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
      if policy.buffer_time_mins.present? && policy.buffer_time_mins > 0 && @booking.staff_member_id.present?
        buffer = policy.buffer_time_mins
        day = @booking.start_time.to_date
        current_business.bookings.where(staff_member_id: @booking.staff_member_id, start_time: day.all_day).each do |existing|
          if @booking.start_time < existing.end_time + buffer.minutes && @booking.end_time > existing.start_time - buffer.minutes
            @booking.errors.add(:base, "Booking conflicts with another existing booking due to buffer time")
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
        return render :new, status: :unprocessable_entity
      end

      if @booking.save
        flash[:notice] = "Booking was successfully created."
        redirect_to business_manager_booking_path(@booking)
      else
        raise "DEBUG: Booking errors: #{@booking.errors.full_messages.inspect}"
        flash.now[:alert] = @booking.errors.full_messages.join(', ')
        render :new, status: :unprocessable_entity
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
      @booking = current_business.bookings.includes(booking_product_add_ons: {product_variant: :product})
                                .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = "Booking not found."
      redirect_to business_manager_bookings_path
    end
    
    def booking_params
      # For complex nested attributes like this, we need to build the permitted parameters
      # differently to handle dynamic keys
      params.require(:booking).permit(
        :notes, 
        :staff_member_id,
        booking_product_add_ons_attributes: [:id, :product_variant_id, :quantity, :_destroy, :price, :total_amount]
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
  end
end 