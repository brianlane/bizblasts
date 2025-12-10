# frozen_string_literal: true

module Public
  class RentalsController < ApplicationController
    before_action :set_rental, only: [:show, :availability, :book, :create_booking, :calendar, :available_slots]
    before_action :set_customer, only: [:create_booking]
    
    # GET /rentals
    def index
      @rentals = current_tenant.products.rentals.active.positioned.includes(images_attachments: :blob)
      
      # Filter by category
      if params[:category].present?
        @rentals = @rentals.where(rental_category: params[:category])
      end
      
      # Filter by location
      if params[:location_id].present?
        @rentals = @rentals.where(location_id: params[:location_id])
      end
      
      @rental_categories = current_tenant.products.rentals.active.distinct.pluck(:rental_category).compact
      @locations = current_tenant.locations
    end
    
    # GET /rentals/:id
    def show
      @variants = @rental.product_variants.where.not(name: 'Default')
      @similar_rentals = current_tenant.products.rentals.active
        .includes(images_attachments: :blob)
        .where(rental_category: @rental.rental_category)
        .where.not(id: @rental.id)
        .limit(4)
      @duration_options = @rental.effective_rental_durations
      @selected_duration = normalize_duration_param(params[:duration])
      @quantity = normalize_quantity_param(params[:quantity])
      @duration_pricing_map = build_duration_pricing_map(@duration_options)
      @pricing_preview = pricing_preview_for(@selected_duration)
      @deposit_preview = deposit_preview_for(@quantity)
      
      # Get availability for next 30 days
      @availability_calendar = RentalAvailabilityService.availability_calendar(
        rental: @rental,
        start_date: Date.current,
        end_date: Date.current + 30.days
      )
    end
    
    # GET /rentals/:id/availability
    def availability
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : start_date + 30.days
      
      calendar = RentalAvailabilityService.availability_calendar(
        rental: @rental,
        start_date: start_date,
        end_date: end_date
      )
      
      render json: calendar
    end

    def calendar
      @duration_options = @rental.effective_rental_durations
      @duration_minutes = normalize_duration_param(params[:duration])
      @quantity = normalize_quantity_param(params[:quantity])
      @duration_pricing_map = build_duration_pricing_map(@duration_options)
      @pricing_preview = pricing_preview_for(@duration_minutes)
      @deposit_preview = deposit_preview_for(@quantity)

      @date = params[:date].present? ? Date.parse(params[:date]) : Date.current
      @calendar_start_date = @date.beginning_of_month.beginning_of_week(:sunday)
      @calendar_end_date = @date.end_of_month.end_of_week(:sunday)
      @calendar_data = rental_calendar_data(@calendar_start_date, @calendar_end_date, @duration_minutes, @quantity)
    rescue ArgumentError
      redirect_to rental_path(@rental), alert: 'Invalid calendar parameters.'
    end

    def available_slots
      date = params[:date].present? ? Date.parse(params[:date]) : Date.current
      duration = params[:duration].to_i
      quantity = params[:quantity].to_i.positive? ? params[:quantity].to_i : 1
      slots = RentalAvailabilityService.available_slots(
        rental: @rental,
        date: date,
        duration_mins: duration,
        quantity: quantity
      )
      render json: { date: date, slots: slots }
    rescue ArgumentError
      render json: { error: 'Invalid date' }, status: :unprocessable_entity
    end
    
    # GET /rentals/:id/book
    def book
      @duration_options = @rental.effective_rental_durations
      @duration_minutes = normalize_duration_param(params[:duration])
      @quantity = normalize_quantity_param(params[:quantity])

      @start_time = params[:start_time].present? ? Time.zone.parse(params[:start_time]) : nil
      unless @start_time
        redirect_to calendar_rental_path(@rental, duration: @duration_minutes, quantity: @quantity),
                    alert: 'Please select a time slot before continuing.' and return
      end

      @end_time = @start_time + @duration_minutes.minutes
      @booking = RentalBooking.new(
        product: @rental,
        start_time: @start_time,
        end_time: @end_time,
        quantity: @quantity
      )
      @pricing = @rental.calculate_rental_price(@start_time, @end_time)
    rescue ArgumentError
      redirect_to calendar_rental_path(@rental, duration: @duration_minutes, quantity: @quantity),
                  alert: 'Invalid time slot selected.' and return
    end
    
    # POST /rentals/:id/create_booking
    def create_booking
      service = RentalBookingService.new(
        rental: @rental,
        tenant_customer: @customer,
        params: booking_params
      )
      
      result = service.create_booking
      
      if result[:success]
        @booking = result[:booking]
        
        # If security deposit required, redirect to payment
        if @booking.security_deposit_amount.to_d > 0
          redirect_to rental_booking_payment_path(@booking)
        else
          # No deposit required - auto-approve
          @booking.update!(status: 'deposit_paid', deposit_status: 'collected')
          redirect_to rental_booking_path(@booking), 
                      notice: 'Your rental has been booked successfully!'
        end
      else
        @booking = RentalBooking.new(booking_params.merge(product: @rental))
        @duration_minutes = booking_params[:duration_mins].to_i
        @duration_minutes = @rental.effective_rental_durations.first unless @duration_minutes.positive?
        @start_time = @booking.start_time
        @end_time = @start_time && (@start_time + @duration_minutes.minutes)
        @quantity = @booking.quantity || 1
        @pricing = if @start_time && @end_time
                     @rental.calculate_rental_price(@start_time, @end_time)
                   end
        flash.now[:alert] = result[:errors].join(', ')
        render :book, status: :unprocessable_content
      end
    end
    
    private
    
    def set_rental
      @rental = current_tenant.products.rentals.active.find(params[:id])
    end
    
    def set_customer
      if user_signed_in? && current_user.client?
        @customer = current_tenant.tenant_customers.find_or_create_by(email: current_user.email) do |c|
          c.first_name = current_user.first_name
          c.last_name = current_user.last_name
          c.phone = current_user.phone
        end
      else
        # Create guest customer from form params
        customer_params = params.require(:customer).permit(:first_name, :last_name, :email, :phone)
        
        @customer = current_tenant.tenant_customers.find_or_initialize_by(email: customer_params[:email])
        @customer.assign_attributes(customer_params)
        
        unless @customer.save
          @booking = RentalBooking.new(booking_params.merge(product: @rental))
          flash.now[:alert] = "Customer information error: #{@customer.errors.full_messages.join(', ')}"
          render :book, status: :unprocessable_content
          return
        end
      end
    end
    
    def booking_params
      params.require(:rental_booking).permit(
        :start_time, :end_time, :duration_mins, :quantity,
        :product_variant_id, :rate_type,
        :customer_notes
      )
    end
    
    def rental_booking_payment_path(booking)
      # This will redirect to the Stripe checkout for security deposit
      pay_deposit_rental_booking_path(booking)
    end

    def rental_calendar_data(start_date, end_date, duration_mins, quantity)
      data = {}
      (start_date..end_date).each do |date|
        slots = RentalAvailabilityService.available_slots(
          rental: @rental,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )
        data[date.to_s] = slots
      end
      data
    end

    def normalize_duration_param(raw_value)
      value = raw_value.to_i
      return @duration_options.first if value <= 0
      @duration_options.include?(value) ? value : @duration_options.first
    end

    def normalize_quantity_param(raw_value)
      qty = raw_value.to_i.positive? ? raw_value.to_i : 1
      max_available = @rental.rental_quantity_available.presence || 1
      qty.clamp(1, max_available)
    end

    def build_duration_pricing_map(durations)
      durations.index_with do |minutes|
        pricing = @rental.calculate_rental_price(Time.current, Time.current + minutes.minutes)
        {
          base_total: pricing&.dig(:total).to_f,
          rate_type: pricing&.dig(:rate_type),
          rate_quantity: pricing&.dig(:quantity),
          label: @rental.duration_in_words(minutes)
        }
      end
    end

    def pricing_preview_for(duration_minutes)
      @duration_pricing_map[duration_minutes] || {}
    end

    def deposit_preview_for(quantity)
      (@rental.security_deposit || 0).to_d * quantity
    end
  end
end

