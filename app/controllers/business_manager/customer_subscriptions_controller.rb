# frozen_string_literal: true

class BusinessManager::CustomerSubscriptionsController < BusinessManager::BaseController
  before_action :set_customer_subscription, only: [:show, :edit, :update, :destroy, :cancel, :billing_history]
  before_action :authorize_subscription_access, only: [:show, :edit, :update, :destroy, :cancel, :billing_history]

  # GET /manage/subscriptions
  def index
    @customer_subscriptions = current_business.customer_subscriptions
                                             .includes(:tenant_customer, :product, :service)
                                             .order(created_at: :desc)
                                             .page(params[:page])
                                             .per(25)

    # Apply filters
    @customer_subscriptions = @customer_subscriptions.where(status: params[:status]) if params[:status].present?
    @customer_subscriptions = @customer_subscriptions.where(subscription_type: params[:type]) if params[:type].present?
    
    # Search by customer name or email
    if params[:search].present?
      @customer_subscriptions = @customer_subscriptions.joins(:tenant_customer)
                                                       .where("tenant_customers.name ILIKE ? OR tenant_customers.email ILIKE ?", 
                                                             "%#{params[:search]}%", "%#{params[:search]}%")
    end

    # Analytics data for dashboard
    @subscription_stats = {
      total_active: current_business.customer_subscriptions.active.count,
      total_revenue: calculate_monthly_revenue,
      product_subscriptions: current_business.customer_subscriptions.product_subscriptions.active.count,
      service_subscriptions: current_business.customer_subscriptions.service_subscriptions.active.count,
      churn_rate: calculate_churn_rate
    }
  end

  # GET /manage/subscriptions/1
  def show
    @subscription_transactions = @customer_subscription.subscription_transactions
                                                       .includes(:order, :booking, :invoice, :payment)
                                                       .order(processed_date: :desc)
                                                       .limit(10)
  end

  # GET /manage/subscriptions/new
  def new
    @customer_subscription = current_business.customer_subscriptions.build
    @tenant_customers = current_business.tenant_customers.active.order(:name)
    @products = current_business.products.active.order(:name)
    @services = current_business.services.active.order(:name)
  end

  # POST /manage/subscriptions
  def create
    @customer_subscription = current_business.customer_subscriptions.build(customer_subscription_params)

    if @customer_subscription.save
      redirect_to [:business_manager, @customer_subscription], 
                  notice: 'Subscription was successfully created.'
    else
      @tenant_customers = current_business.tenant_customers.active.order(:name)
      @products = current_business.products.active.order(:name)
      @services = current_business.services.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  # GET /manage/subscriptions/1/edit
  def edit
    @tenant_customers = current_business.tenant_customers.active.order(:name)
    @products = current_business.products.active.order(:name)
    @services = current_business.services.active.order(:name)
  end

  # PATCH/PUT /manage/subscriptions/1
  def update
    if @customer_subscription.update(customer_subscription_params)
      redirect_to [:business_manager, @customer_subscription], 
                  notice: 'Subscription was successfully updated.'
    else
      @tenant_customers = current_business.tenant_customers.active.order(:name)
      @products = current_business.products.active.order(:name)
      @services = current_business.services.active.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /manage/subscriptions/1
  def destroy
    if @customer_subscription.cancel!
      @customer_subscription.update!(cancellation_reason: "Cancelled by business manager")
      redirect_to business_manager_customer_subscriptions_url, 
                  notice: 'Subscription was successfully cancelled.'
    else
      redirect_to business_manager_customer_subscriptions_url, 
                  alert: 'Unable to cancel subscription.'
    end
  end



  # PATCH /manage/subscriptions/1/cancel
  def cancel
    reason = params[:cancellation_reason] || "Cancelled by business manager"
    if @customer_subscription.can_be_cancelled?
      if @customer_subscription.cancel!
        @customer_subscription.update!(cancellation_reason: reason) if reason.present?
        redirect_to [:business_manager, @customer_subscription], 
                    notice: 'Subscription has been cancelled.'
      else
        redirect_to [:business_manager, @customer_subscription], 
                    alert: 'Unable to cancel subscription.'
      end
    else
      redirect_to [:business_manager, @customer_subscription], 
                  alert: 'Unable to cancel subscription.'
    end
  end

  # GET /manage/subscriptions/1/billing_history
  def billing_history
    @subscription_transactions = @customer_subscription.subscription_transactions
                                                       .includes(:order, :booking, :invoice, :payment)
                                                       .order(processed_date: :desc)
                                                       .page(params[:page])
                                                       .per(25)
  end

  # GET /manage/subscriptions/analytics
  def analytics
    @analytics_data = {
      monthly_revenue: monthly_revenue_data,
      subscription_growth: subscription_growth_data,
      churn_analysis: churn_analysis_data,
      product_performance: product_subscription_performance,
      service_performance: service_subscription_performance
    }

    respond_to do |format|
      format.html
      format.json { render json: @analytics_data }
    end
  end

  private

  def set_customer_subscription
    # Ensure we're in the correct tenant context and scope to current business
    unless ActsAsTenant.current_tenant == current_business
      raise ActiveRecord::RecordNotFound
    end
    
    @customer_subscription = current_business.customer_subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound
  end

  def authorize_subscription_access
    unless @customer_subscription.business == current_business
      redirect_to business_manager_customer_subscriptions_path, 
                  alert: 'Access denied.'
    end
  end

  def customer_subscription_params
    params.require(:customer_subscription).permit(
      :tenant_customer_id, :product_id, :service_id, :product_variant_id,
      :quantity, :next_billing_date, :billing_day_of_month, :subscription_type,
      :frequency, :subscription_price, :customer_rebooking_preference,
      :customer_out_of_stock_preference, :service_rebooking_preference, 
      :preferred_time_slot, :preferred_staff_member_id, :out_of_stock_action, :notes
    )
  end

  def calculate_monthly_revenue
    current_business.customer_subscriptions.active.sum(:subscription_price)
  end

  def calculate_churn_rate
    # Calculate churn rate over the last 30 days
    total_active_start = current_business.customer_subscriptions
                                       .where('created_at <= ?', 30.days.ago)
                                       .count
    
    cancelled_in_period = current_business.customer_subscriptions
                                        .where(cancelled_at: 30.days.ago..Time.current)
                                        .count
    
    return 0 if total_active_start.zero?
    ((cancelled_in_period.to_f / total_active_start) * 100).round(2)
  end

  def monthly_revenue_data
    # Get revenue data for the last 12 months
    data = {}
    start_date = 11.months.ago.beginning_of_month.to_date
    end_date = Date.current.end_of_month
    
    (start_date..end_date).step(1.month) do |date|
      data[date.strftime('%B %Y')] = current_business.customer_subscriptions
                                                   .where(status: :active)
                                                   .where('created_at <= ?', date.end_of_month)
                                                   .sum(:subscription_price)
    end
    data
  end

  def subscription_growth_data
    # Get subscription count growth for the last 12 months
    data = {}
    start_date = 11.months.ago.beginning_of_month.to_date
    end_date = Date.current.end_of_month
    
    (start_date..end_date).step(1.month) do |date|
      data[date.strftime('%B %Y')] = current_business.customer_subscriptions
                                                   .where('created_at <= ?', date.end_of_month)
                                                   .where(status: :active)
                                                   .count
    end
    data
  end

  def churn_analysis_data
    # Analyze churn by month for the last 6 months
    start_date = 5.months.ago.beginning_of_month.to_date
    end_date = Date.current.end_of_month
    
    (start_date..end_date).step(1.month).map do |date|
      {
        month: date.strftime('%B %Y'),
        cancelled: current_business.customer_subscriptions
                                 .where(cancelled_at: date.beginning_of_month..date.end_of_month)
                                 .count,
        created: current_business.customer_subscriptions
                               .where(created_at: date.beginning_of_month..date.end_of_month)
                               .count
      }
    end
  end

  def product_subscription_performance
    current_business.products
                  .joins(:customer_subscriptions)
                  .where(customer_subscriptions: { status: :active })
                  .group('products.name')
                  .count
  end

  def service_subscription_performance
    current_business.services
                  .joins(:customer_subscriptions)
                  .where(customer_subscriptions: { status: :active })
                  .group('services.name')
                  .count
  end
end 
 
 
 
 