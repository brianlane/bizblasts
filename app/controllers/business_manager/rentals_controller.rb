# frozen_string_literal: true

module BusinessManager
  class RentalsController < BaseController
    before_action :set_rental, only: [:show, :edit, :update, :destroy, :update_position, :availability, :manage_availability, :update_availability]
    
    # GET /manage/rentals
    def index
      @rentals = current_business.products.rentals.positioned.includes(:product_variants, :location, images_attachments: :blob)
      
      # Filter by category if specified
      if params[:category].present?
        @rentals = @rentals.where(rental_category: params[:category])
      end
      
      # Filter by location if specified
      if params[:location_id].present?
        @rentals = @rentals.where(location_id: params[:location_id])
      end
      
      @rental_categories = Product::RENTAL_CATEGORIES
      @locations = current_business.locations
      
      # Apply pagination if available
      @rentals = @rentals.page(params[:page]) if @rentals.respond_to?(:page)
    end
    
    # GET /manage/rentals/:id
    def show
      @recent_bookings = @rental.rental_bookings
        .includes(:tenant_customer)
        .order(created_at: :desc)
        .limit(10)
      @availability_calendar = RentalAvailabilityService.availability_calendar(
        rental: @rental,
        start_date: Date.current,
        end_date: Date.current + 30.days
      )
    end
    
    # GET /manage/rentals/new
    def new
      @rental = current_business.products.new(product_type: :rental)
      @locations = current_business.locations
    end
    
    # POST /manage/rentals
    def create
      @rental = current_business.products.new(rental_params)
      @rental.product_type = :rental
      
      if @rental.save
        redirect_to business_manager_rental_path(@rental), notice: 'Rental item was successfully created.'
      else
        @locations = current_business.locations
        flash.now[:alert] = @rental.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end
    
    # GET /manage/rentals/:id/edit
    def edit
      @locations = current_business.locations
    end
    
    # PATCH/PUT /manage/rentals/:id
    def update
      success = false
      
      # Wrap in transaction to ensure atomicity - if image handling fails,
      # the rental update is rolled back
      Product.transaction do
        if @rental.update(rental_params_without_images)
          if handle_image_updates
            success = true
          else
            # Image handling failed - rollback the rental update
            raise ActiveRecord::Rollback
          end
        end
      end
      
      if success
        redirect_to business_manager_rental_path(@rental), notice: 'Rental item was successfully updated.'
      else
        @locations = current_business.locations
        flash.now[:alert] = @rental.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end
    
    # DELETE /manage/rentals/:id
    def destroy
      if @rental.rental_bookings.where.not(status: ['cancelled', 'completed']).exists?
        redirect_to business_manager_rentals_path, alert: 'Cannot delete rental with active bookings.'
      else
        @rental.destroy
        redirect_to business_manager_rentals_path, notice: 'Rental item was successfully deleted.'
      end
    end
    
    # PATCH /manage/rentals/:id/update_position
    def update_position
      new_position = params[:position].to_i
      
      if @rental.move_to_position(new_position)
        render json: { status: 'success', message: 'Rental position updated successfully' }
      else
        render json: { status: 'error', message: 'Failed to update rental position' }, status: :unprocessable_content
      end
    end
    
    # GET /manage/rentals/:id/availability
    def availability
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : start_date + 30.days
      
      @calendar = RentalAvailabilityService.availability_calendar(
        rental: @rental,
        start_date: start_date,
        end_date: end_date,
        bust_cache: params[:bust_cache].present?
      )
      
      respond_to do |format|
        format.html
        format.json { render json: @calendar }
      end
    end

    def manage_availability
      authorize @rental
      prepare_availability_context
    end

    def update_availability
      authorize @rental
      prepare_availability_context

      availability_payload = build_rental_availability_payload
      final_payload = if params.dig(:product, :only_current_week) == '1'
                        merge_current_week_overrides(availability_payload)
                      else
                        availability_payload
                      end

      if @rental.update(rental_availability_schedule: final_payload)
        redirect_to manage_availability_business_manager_rental_path(@rental, date: @date), notice: 'Rental availability updated.'
      else
        flash.now[:alert] = @rental.errors.full_messages.to_sentence.presence || 'Unable to update rental availability.'
        render :manage_availability, status: :unprocessable_content
      end
    end
    
    private
    
    def set_rental
      @rental = current_business.products.rentals.find(params[:id])
    end
    
    def rental_params
      params.require(:product).permit(
        # Basic product fields
        :name, :description, :price, :active, :featured,
        :stock_quantity,
        :show_stock_to_customers, :hide_when_out_of_stock,
        :variant_label_text, :position,
        
        # Rental-specific fields
        :hourly_rate, :weekly_rate, :security_deposit,
        :rental_quantity_available, :rental_category,
        :min_rental_duration_mins, :max_rental_duration_mins,
        :rental_buffer_mins,
        :allow_hourly_rental, :allow_daily_rental, :allow_weekly_rental,
        :location_id,
        rental_duration_options: [],
        
        # Images
        images: [],
        images_attributes: [:id, :primary, :position, :_destroy],
        
        # Variants
        product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :_destroy]
      )
    end
    
    def rental_params_without_images
      rental_params.except(:images)
    end
    
    def handle_image_updates
      new_images = params.dig(:product, :images)
      
      if new_images.present?
        valid_images = Array(new_images).compact.reject(&:blank?)
        
        if valid_images.any?
          @rental.images.attach(valid_images)
          
          if @rental.images.any? { |img| !img.persisted? }
            @rental.errors.add(:images, "Failed to attach some images")
            return false
          end
        end
      end
      
      true
    rescue => e
      @rental.errors.add(:images, "Error processing images: #{e.message}")
      false
    end

    def prepare_availability_context
      @date = params[:date].present? ? Date.parse(params[:date]) : Date.current
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
      @calendar_data = build_calendar_preview
    end

    def build_calendar_preview
      tz = @rental.business&.time_zone.presence || 'UTC'
      data = {}

      Time.use_zone(tz) do
        (@start_date..@end_date).each do |date|
          data[date.to_s] = Array(@rental.rental_schedule_for(date))
        end
      end

      data
    end

    def build_rental_availability_payload
      days = (%w[monday tuesday wednesday thursday friday saturday sunday]).index_with { [] }
      days['exceptions'] = {}

      availability_params = availability_permitted_params
      full_day_params = params[:full_day] || {}

      days.keys.each do |day|
        next if day == 'exceptions'

        if full_day_params[day] == '1'
          days[day] = [{ 'start' => '00:00', 'end' => '23:59' }]
        else
          slot_hash = availability_params[day]
          slots = if slot_hash.is_a?(Hash)
                    slot_hash.values
                  elsif slot_hash.is_a?(Array)
                    slot_hash
                  else
                    []
                  end

          days[day] = slots.filter_map do |slot|
            start_time = slot['start'] || slot[:start]
            end_time = slot['end'] || slot[:end]
            next if start_time.blank? || end_time.blank?
            { 'start' => start_time, 'end' => end_time }
          end
        end
      end

      days
    end

    def merge_current_week_overrides(base_schedule)
      schedule = (@rental.rental_availability_schedule || {}).deep_dup
      schedule = schedule.with_indifferent_access
      schedule[:exceptions] ||= {}

      (@start_date..@end_date).each do |date|
        day_key = date.strftime('%A').downcase
        schedule[:exceptions][date.iso8601] = base_schedule[day_key] || []
      end

      schedule
    end

    def availability_permitted_params
      return {} unless params[:product].present? && params[:product][:availability].present?

      params.require(:product).require(:availability).permit(
        monday: permit_dynamic_slots,
        tuesday: permit_dynamic_slots,
        wednesday: permit_dynamic_slots,
        thursday: permit_dynamic_slots,
        friday: permit_dynamic_slots,
        saturday: permit_dynamic_slots,
        sunday: permit_dynamic_slots,
        exceptions: {}
      ).to_h
    rescue ActionController::ParameterMissing
      {}
    end

    def permit_dynamic_slots
      Hash.new { |h, k| h[k] = [:start, :end] }
    end
  end
end

