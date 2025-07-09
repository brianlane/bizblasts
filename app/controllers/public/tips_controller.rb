class Public::TipsController < Public::BaseController
  after_action :no_store!
  before_action :set_tenant
  before_action :set_booking_from_token, only: [:new, :create]
  before_action :validate_tip_eligibility, only: [:new, :create]
  
  def new
    @tip = Tip.new(booking: @booking)
    @base_amount = @booking.total_charge
    @tip_config = @booking.business.tip_configuration_or_default
  end

  def create
    tip_amount = params[:tip_amount].to_f
    
    # Validate tip amount
    if tip_amount < 0.50
      flash[:alert] = "Minimum tip amount is $0.50."
      redirect_to new_tip_path(booking_id: @booking.id, token: params[:token]) and return
    end

    @tip = Tip.new(
      booking: @booking,
      business: @booking.business,
      tenant_customer: @booking.tenant_customer,
      amount: tip_amount,
      status: :pending
    )

    if @tip.save
      begin
        # Create Stripe checkout session for tip payment
        success_url = success_tip_url(@tip, token: params[:token], host: request.host_with_port)
        cancel_url = cancel_tip_url(@tip, token: params[:token], host: request.host_with_port)
        
        result = StripeService.create_tip_payment_session(
          tip: @tip,
          success_url: success_url,
          cancel_url: cancel_url
        )
        
        redirect_to result[:session].url, allow_other_host: true
      rescue ArgumentError => e
        @tip.destroy
        flash[:alert] = e.message
        redirect_to new_tip_path(booking_id: @booking.id, token: params[:token])
      rescue Stripe::StripeError => e
        @tip.destroy
        flash[:alert] = "Could not connect to payment processor: #{e.message}"
        redirect_to new_tip_path(booking_id: @booking.id, token: params[:token])
      end
    else
      flash[:alert] = @tip.errors.full_messages.to_sentence
      redirect_to new_tip_path(booking_id: @booking.id, token: params[:token])
    end
  end

  def show
    @tip = current_tenant.tips.find(params[:id])
    @booking = @tip.booking
    
    # Verify token access
    unless params[:token].present? && Booking.verify_tip_token(params[:token]) == @booking
      flash[:alert] = "Invalid or expired access token."
      redirect_to tenant_root_path and return
    end
  end

  def success
    @tip = current_tenant.tips.find(params[:id])
    @booking = @tip.booking
    
    # Verify token access
    unless params[:token].present? && Booking.verify_tip_token(params[:token]) == @booking
      flash[:alert] = "Invalid or expired access token."
      redirect_to tenant_root_path and return
    end
    
    # Check if tip was successfully processed
    if @tip.completed?
      flash[:notice] = "Thank you for your tip! Your appreciation means a lot to our team."
    else
      flash[:alert] = "There was an issue processing your tip. Please try again or contact us for assistance."
    end
    
    # Redirect to booking page
    redirect_to tenant_my_booking_path(@booking)
  end

  def cancel
    @tip = current_tenant.tips.find(params[:id])
    @booking = @tip.booking
    
    # Verify token access
    unless params[:token].present? && Booking.verify_tip_token(params[:token]) == @booking
      flash[:alert] = "Invalid or expired access token."
      redirect_to tenant_root_path and return
    end
    
    # Only destroy pending tips
    if @tip.pending?
      @tip.destroy
      flash[:notice] = "Tip payment was cancelled."
    else
      flash[:alert] = "Cannot cancel a completed tip."
    end
    
    # Redirect to booking page
    redirect_to tenant_my_booking_path(@booking)
  end

  private

  def set_booking_from_token
    booking_id = params[:booking_id] || params[:id]
    token = params[:token]
    
    unless booking_id.present? && token.present?
      flash[:alert] = "Invalid access link."
      redirect_to tenant_root_path and return
    end

    @booking = current_tenant.bookings.find_by(id: booking_id)
    
    unless @booking
      flash[:alert] = "Booking not found."
      redirect_to tenant_root_path and return
    end

    unless Booking.verify_tip_token(token) == @booking
      flash[:alert] = "Invalid or expired access token."
      redirect_to tenant_root_path and return
    end
  end

  def validate_tip_eligibility
    # Check if service is eligible for tips
    unless @booking.service.experience? && @booking.service.tips_enabled?
      flash[:alert] = "This service is not eligible for tips."
      redirect_to tenant_my_booking_path(@booking) and return
    end

    # Check if tip already exists
    if @booking.tip.present?
      flash[:notice] = "A tip has already been provided for this booking."
      redirect_to "#{tip_path(@booking.tip)}?token=#{params[:token]}" and return
    end
  end

  def current_tenant
    ActsAsTenant.current_tenant
  end
  
  # Skip authentication for token-based tip access
  def skip_user_authentication?
    true
  end
end 