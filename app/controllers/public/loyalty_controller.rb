class Public::LoyaltyController < PublicController
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_current_customer
  before_action :set_business, only: [:show, :redeem_points]
  before_action :set_customer, only: [:show, :redeem_points]
  before_action :check_loyalty_program_enabled, only: [:show, :redeem_points]
  
  def index
    @businesses_with_points = get_businesses_with_points
    @total_points_across_businesses = calculate_total_points
  end
  
  def show
    if @customer
      @loyalty_summary = LoyaltyPointsService.get_customer_summary(@customer)
      @loyalty_history = @customer.loyalty_points_history
      @redemption_options = LoyaltyPointsService.get_redemption_options(@customer)
      @active_redemptions = @business.discount_codes.where(tenant_customer: @customer, active: true).where('points_redeemed > 0')
    else
      @loyalty_summary = nil
      @loyalty_history = []
      @redemption_options = []
      @active_redemptions = []
    end
  end
  
  def redeem_points
    return redirect_to_loyalty_page(@business, 'No loyalty account found') unless @customer
    
    points = params[:points].to_i
    
    # Validate points amount
    if points <= 0
      return redirect_to_loyalty_page(@business, 'Invalid points amount')
    end
    
    result = LoyaltyPointsService.redeem_points_for_discount(
      customer: @customer,
      points: points,
      description: "Redeemed #{points} points for discount code"
    )
    
    if result[:success]
      redirect_to_loyalty_page(@business, 
        "Successfully redeemed #{points} points! Your discount code is: #{result[:discount_code]}")
    else
      redirect_to_loyalty_page(@business, result[:error])
    end
  end
  

  

  
    private
  
  def ensure_client_user
    redirect_to root_path, alert: 'Access denied' unless current_user&.client?
  end

  def set_current_customer
    # This is for the general loyalty index - we'll find customers per business
  end

  def set_business
    # For subdomain routes (tenant loyalty), use current tenant
    @business = ActsAsTenant.current_tenant
    raise ActiveRecord::RecordNotFound, "Business not found" unless @business
  end

  def set_customer
    return unless current_user && @business
    @customer = TenantCustomer.find_by(email: current_user.email, business: @business)
  end

  def check_loyalty_program_enabled
    return if @business&.loyalty_program_enabled?
    redirect_to root_path, alert: 'Loyalty program is not available for this business'
  end
  
  def get_businesses_with_points
    # Find all businesses where this user has loyalty points
    customer_emails = [current_user.email]
    
    TenantCustomer.joins(:loyalty_transactions, :business)
                  .where(email: customer_emails)
                  .group('businesses.id, businesses.name, businesses.hostname')
                  .having('SUM(loyalty_transactions.points_amount) > 0')
                  .pluck('businesses.id', 'businesses.name', 'businesses.hostname', 'SUM(loyalty_transactions.points_amount)')
                  .map do |id, name, hostname, points|
                    {
                      business_id: id,
                      business_name: name,
                      business_hostname: hostname,
                      current_points: points,
                      customer: TenantCustomer.find_by(email: current_user.email, business_id: id)
                    }
                  end
  end
  
  def calculate_total_points
    customer_emails = [current_user.email]
    
    TenantCustomer.joins(:loyalty_transactions)
                  .where(email: customer_emails)
                  .sum('loyalty_transactions.points_amount')
  end
  
  def find_customer_for_business(business)
    TenantCustomer.find_by(email: current_user.email, business: business)
  end
  
  def redirect_to_loyalty_page(business, message)
    if message.include?('Successfully')
      redirect_to tenant_loyalty_path, notice: message
    else
      redirect_to tenant_loyalty_path, alert: message
    end
  end
  

  

end 