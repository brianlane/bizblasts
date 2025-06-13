class TipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_booking
  before_action :check_tip_eligibility
  
  def new
    @tip = @booking.build_tip(tenant_customer: current_tenant_customer)
  end
  
  def create
    @tip = @booking.build_tip(tip_params.merge(
      business: current_business,
      tenant_customer: current_tenant_customer
    ))
    
    if @tip.save
      begin
        # Create Stripe checkout session for tip payment
        result = StripeService.create_tip_checkout_session(
          tip: @tip,
          success_url: tenant_tip_success_url(@tip, host: request.host_with_port),
          cancel_url: tenant_tip_cancel_url(@tip, host: request.host_with_port)
        )
        
        redirect_to result[:session].url
      rescue Stripe::StripeError => e
        Rails.logger.error "[TIP] Stripe error for tip #{@tip.id}: #{e.message}"
        @tip.destroy
        flash[:alert] = "Could not connect to Stripe for tip payment. Please try again."
        redirect_to tenant_booking_path(@booking)
      rescue ArgumentError => e
        Rails.logger.error "[TIP] Tip amount error for tip #{@tip.id}: #{e.message}"
        @tip.destroy
        flash[:alert] = e.message
        redirect_to tenant_booking_path(@booking)
      end
    else
      render :new
    end
  end
  
  def success
    @tip = Tip.find(params[:id])
    flash[:notice] = "Thank you for your tip! Your payment has been processed."
    redirect_to tenant_booking_path(@tip.booking)
  end
  
  def cancel
    @tip = Tip.find(params[:id])
    @tip.destroy if @tip.pending?
    flash[:notice] = "Tip payment was cancelled."
    redirect_to tenant_booking_path(@tip.booking)
  end
  
  private
  
  def set_booking
    @booking = current_business.bookings.find(params[:booking_id])
  end
  
  def check_tip_eligibility
    unless @booking.eligible_for_tips?
      flash[:alert] = "This booking is not eligible for tips yet."
      redirect_to tenant_booking_path(@booking)
    end
    
    if @booking.tip_processed?
      flash[:alert] = "A tip has already been processed for this booking."
      redirect_to tenant_booking_path(@booking)
    end
  end
  
  def tip_params
    params.require(:tip).permit(:amount)
  end
  
  def current_tenant_customer
    @current_tenant_customer ||= current_business.tenant_customers.find_by(email: current_user.email)
  end
end 