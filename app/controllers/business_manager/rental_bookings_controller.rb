# frozen_string_literal: true

module BusinessManager
  class RentalBookingsController < BaseController
    before_action :set_rental_booking, only: [:show, :edit, :update, :check_out, :process_return, :complete, :cancel]
    before_action :set_rentals, only: [:new, :create, :edit, :update]
    
    # GET /manage/rental_bookings
    def index
      @rental_bookings = current_business.rental_bookings
        .includes(:product, :tenant_customer, :location)
        .order(start_time: :desc)
      
      # Filter by status
      if params[:status].present?
        @rental_bookings = @rental_bookings.where(status: params[:status])
      end
      
      # Filter by rental product
      if params[:product_id].present?
        @rental_bookings = @rental_bookings.where(product_id: params[:product_id])
      end
      
      # Filter by date range
      if params[:start_date].present?
        @rental_bookings = @rental_bookings.where('start_time >= ?', Date.parse(params[:start_date]).beginning_of_day)
      end
      if params[:end_date].present?
        @rental_bookings = @rental_bookings.where('end_time <= ?', Date.parse(params[:end_date]).end_of_day)
      end
      
      # Summary counts for tabs
      @pending_count = current_business.rental_bookings.status_pending_deposit.count
      @active_count = current_business.rental_bookings.active.count
      @overdue_count = current_business.rental_bookings.overdue_rentals.count
      @today_pickups_count = current_business.rental_bookings.today_pickups.count
      @today_returns_count = current_business.rental_bookings.today_returns.count
      
      @rental_bookings = @rental_bookings.page(params[:page]) if @rental_bookings.respond_to?(:page)
    end
    
    # GET /manage/rental_bookings/:id
    def show
      @condition_reports = @rental_booking.rental_condition_reports.order(created_at: :desc)
    end
    
    # GET /manage/rental_bookings/new
    def new
      @rental_booking = current_business.rental_bookings.new
      @customers = current_business.tenant_customers.order(:first_name, :last_name)
    end
    
    # POST /manage/rental_bookings
    def create
      rental = current_business.products.rentals.find_by(id: params[:rental_booking][:product_id])
      
      unless rental
        redirect_to new_business_manager_rental_booking_path, alert: 'Please select a valid rental item.'
        return
      end
      
      customer = find_or_create_customer
      unless customer
        redirect_to new_business_manager_rental_booking_path, alert: 'Customer information is required.'
        return
      end
      
      service = RentalBookingService.new(
        rental: rental,
        tenant_customer: customer,
        params: rental_booking_params
      )
      
      result = service.create_booking
      
      if result[:success]
        redirect_to business_manager_rental_booking_path(result[:booking]), 
                    notice: 'Rental booking was successfully created.'
      else
        @rental_booking = current_business.rental_bookings.new(rental_booking_params)
        @customers = current_business.tenant_customers.order(:first_name, :last_name)
        flash.now[:alert] = result[:errors].join(', ')
        render :new, status: :unprocessable_content
      end
    end
    
    # GET /manage/rental_bookings/:id/edit
    def edit
      @customers = current_business.tenant_customers.order(:first_name, :last_name)
    end
    
    # PATCH/PUT /manage/rental_bookings/:id
    def update
      if @rental_booking.update(update_booking_params)
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    notice: 'Rental booking was successfully updated.'
      else
        @customers = current_business.tenant_customers.order(:first_name, :last_name)
        flash.now[:alert] = @rental_booking.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end
    
    # PATCH /manage/rental_bookings/:id/check_out
    def check_out
      unless @rental_booking.can_check_out?
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'This rental cannot be checked out at this time.'
        return
      end
      
      if @rental_booking.check_out!(
        staff_member: current_staff_member,
        condition_notes: params[:condition_notes],
        checklist_items: params[:checklist_items] || []
      )
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    notice: 'Rental has been checked out successfully.'
      else
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'Failed to check out rental.'
      end
    end
    
    # PATCH /manage/rental_bookings/:id/process_return
    def process_return
      unless @rental_booking.can_return?
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'This rental cannot be returned at this time.'
        return
      end
      
      if @rental_booking.process_return!(
        staff_member: current_staff_member,
        condition_rating: params[:condition_rating] || 'good',
        notes: params[:return_notes],
        damage_amount: params[:damage_amount].to_d,
        checklist_items: params[:checklist_items] || []
      )
        # Auto-complete if no issues
        @rental_booking.complete! if @rental_booking.deposit_full_refund?
        
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    notice: 'Return has been processed successfully.'
      else
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'Failed to process return.'
      end
    end
    
    # PATCH /manage/rental_bookings/:id/complete
    def complete
      if @rental_booking.complete!
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    notice: 'Rental has been marked as completed.'
      else
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'Cannot complete this rental.'
      end
    end
    
    # PATCH /manage/rental_bookings/:id/cancel
    def cancel
      if @rental_booking.cancel!(reason: params[:cancellation_reason])
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    notice: 'Rental has been cancelled.'
      else
        redirect_to business_manager_rental_booking_path(@rental_booking), 
                    alert: 'Cannot cancel this rental.'
      end
    end
    
    # GET /manage/rental_bookings/calendar
    def calendar
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      @end_date = @start_date.end_of_month
      
      @bookings = current_business.rental_bookings
        .where.not(status: :cancelled)
        .where('start_time < ? AND end_time > ?', @end_date.end_of_day, @start_date.beginning_of_day)
        .includes(:product, :tenant_customer)
      
      @rentals = current_business.products.rentals.active
    end
    
    # GET /manage/rental_bookings/overdue
    def overdue
      @rental_bookings = current_business.rental_bookings
        .overdue_rentals
        .includes(:product, :tenant_customer)
        .order(end_time: :asc)
    end
    
    private
    
    def set_rental_booking
      @rental_booking = current_business.rental_bookings.find(params[:id])
    end
    
    def set_rentals
      @rentals = current_business.products.rentals.active.positioned
    end
    
    def rental_booking_params
      params.require(:rental_booking).permit(
        :product_id, :product_variant_id, :tenant_customer_id,
        :start_time, :end_time, :quantity,
        :rate_type, :location_id, :promotion_id,
        :customer_notes, :notes
      )
    end
    
    def update_booking_params
      # Only allow updating certain fields based on status
      if @rental_booking.status_pending_deposit? || @rental_booking.status_deposit_paid?
        params.require(:rental_booking).permit(
          :start_time, :end_time, :quantity,
          :customer_notes, :notes, :location_id
        )
      else
        params.require(:rental_booking).permit(:notes)
      end
    end
    
    def find_or_create_customer
      if params[:rental_booking][:tenant_customer_id].present?
        current_business.tenant_customers.find_by(id: params[:rental_booking][:tenant_customer_id])
      elsif params[:customer].present?
        customer_params = params.require(:customer).permit(:first_name, :last_name, :email, :phone)
        
        # Try to find existing customer by email
        customer = current_business.tenant_customers.find_by(email: customer_params[:email])
        customer || current_business.tenant_customers.create(customer_params)
      end
    end
    
    def current_staff_member
      @current_staff_member ||= current_business.staff_members.find_by(user: current_user)
    end
  end
end

