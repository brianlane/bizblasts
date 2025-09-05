# frozen_string_literal: true

class Client::SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_client_role
  before_action :set_subscription, only: [:show, :edit, :update, :cancel, :billing_history, :preferences, :update_preferences]

  # GET /subscriptions
  def index
    # Get all subscriptions for this user based on email match
    @customer_subscriptions = CustomerSubscription.joins(:tenant_customer)
                                                 .where(tenant_customers: { email: current_user.email })
                                                 .includes(:business, :product, :service, :tenant_customer)
                                                 .order(created_at: :desc)

    # Apply filters
    @customer_subscriptions = @customer_subscriptions.where(status: params[:status]) if params[:status].present?
    @customer_subscriptions = @customer_subscriptions.where(subscription_type: params[:type]) if params[:type].present?
    
    # Filter by business
    if params[:business_id].present?
      @customer_subscriptions = @customer_subscriptions.where(business_id: params[:business_id])
    end

    # Get list of businesses for filter dropdown
    @businesses = Business.joins(:customer_subscriptions)
                         .joins('JOIN tenant_customers ON customer_subscriptions.tenant_customer_id = tenant_customers.id')
                         .where(tenant_customers: { email: current_user.email })
                         .distinct
                         .order(:name)
  end

  # GET /subscriptions/1
  def show
    @subscription_transactions = @customer_subscription.subscription_transactions
                                                      .includes(:order, :booking, :invoice, :payment)
                                                      .order(processed_date: :desc)
                                                      .limit(10)
  end

  # GET /subscriptions/1/edit
  def edit
    # Only allow editing certain fields for clients
    # Quantity, preferences, etc. - not pricing or core subscription details
  end

  # PATCH/PUT /subscriptions/1
  def update
    if @customer_subscription.update(client_subscription_params)
      redirect_to client_subscription_path(@customer_subscription), notice: 'Subscription updated successfully'
    else
      render :edit, status: :unprocessable_content
    end
  end

  # GET /subscriptions/1/preferences
  def preferences
    # Load form for customer preferences
  end

  # PATCH /subscriptions/1/update_preferences
  def update_preferences
    if @customer_subscription.update(client_subscription_params)
      redirect_to client_subscription_path(@customer_subscription), notice: 'Preferences updated successfully'
    else
      render :preferences, status: :unprocessable_content
    end
  end

  # GET /subscriptions/1/cancel
  # POST /subscriptions/1/cancel
  def cancel
    if request.post? && params[:confirmed] == 'true'
      if @customer_subscription.can_be_cancelled?
        @customer_subscription.cancel!
        redirect_to client_subscriptions_path, notice: 'Subscription cancelled successfully'
      else
        redirect_to client_subscription_path(@customer_subscription), alert: 'Cannot cancel this subscription at this time.'
      end
    else
      # Show confirmation page (for both GET and POST without confirmation)
      render :cancel
    end
  end



  # GET /subscriptions/1/billing_history
  def billing_history
    @subscription_transactions = @customer_subscription.subscription_transactions
                                                      .includes(:order, :booking, :invoice, :payment)
                                                      .order(processed_date: :desc)
                                                      .page(params[:page])
                                                      .per(15)
    @transactions = @subscription_transactions  # For test compatibility
  end

  private

  def ensure_client_role
    unless current_user&.client?
      if current_user&.manager?
        redirect_to business_manager_dashboard_path, alert: 'You do not have permission to access this area.'
      else
        redirect_to root_path, alert: 'You do not have permission to access this area.'
      end
    end
  end

  def set_subscription
    # Ensure we're in the correct tenant context
    unless ActsAsTenant.current_tenant
      raise ActiveRecord::RecordNotFound
    end
    
    @customer_subscription = current_user_subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound
  end

  def current_user_subscriptions
    # Get all subscriptions for the current user based on email match
    # and ensure they belong to the current tenant
    CustomerSubscription.joins(:tenant_customer)
                       .where(tenant_customers: { email: current_user.email })
                       .where(business: ActsAsTenant.current_tenant)
  end

  def client_subscription_params
    # Only allow clients to modify certain fields
    params.require(:customer_subscription).permit(
      :quantity, :customer_rebooking_preference, :customer_out_of_stock_preference,
      :preferred_time_slot, :preferred_staff_member_id, :notes
    )
  end
end 
 
 