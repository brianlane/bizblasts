# frozen_string_literal: true

module Public
  class RentalsController < ApplicationController
    before_action :set_rental, only: [:show, :availability, :book, :create_booking]
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
        .where(rental_category: @rental.rental_category)
        .where.not(id: @rental.id)
        .limit(4)
      
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
    
    # GET /rentals/:id/book
    def book
      # Check if rental requires authentication
      @booking = RentalBooking.new(
        product: @rental,
        start_time: params[:start_time],
        end_time: params[:end_time],
        quantity: params[:quantity] || 1
      )
      
      # Pre-calculate pricing if dates provided
      if params[:start_time].present? && params[:end_time].present?
        start_time = Time.zone.parse(params[:start_time])
        end_time = Time.zone.parse(params[:end_time])
        @pricing = @rental.calculate_rental_price(start_time, end_time, rate_type: params[:rate_type])
      end
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
          redirect_to tenant_rental_booking_path(@booking), 
                      notice: 'Your rental has been booked successfully!'
        end
      else
        @booking = RentalBooking.new(booking_params.merge(product: @rental))
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
        :start_time, :end_time, :quantity,
        :product_variant_id, :rate_type,
        :customer_notes
      )
    end
    
    def rental_booking_payment_path(booking)
      # This will redirect to the Stripe checkout for security deposit
      tenant_rental_booking_pay_deposit_path(booking)
    end
  end
end

