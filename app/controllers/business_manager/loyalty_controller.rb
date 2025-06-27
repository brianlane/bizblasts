class BusinessManager::LoyaltyController < BusinessManager::BaseController
  before_action :set_loyalty_program, only: [:show, :edit, :update]
  
  def index
    # Ensure loyalty program exists if enabled
    ensure_loyalty_program! if current_business.loyalty_program_enabled?
    
    @loyalty_program = current_business.loyalty_programs.first || current_business.loyalty_programs.build
    @loyalty_stats = calculate_loyalty_stats
    @recent_transactions = current_business.loyalty_transactions.includes(:tenant_customer).recent.limit(20)
  end
  
  def show
    @loyalty_transactions = current_business.loyalty_transactions
                                          .includes(:tenant_customer)
                                          .recent
                                          .page(params[:page])
    @loyalty_stats = calculate_loyalty_stats
  end
  
  def edit
  end
  
  def update
    if @loyalty_program.update(loyalty_program_params)
      redirect_to business_manager_loyalty_index_path, notice: 'Loyalty program updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def create
    @loyalty_program = current_business.loyalty_programs.build(loyalty_program_params)
    
    if @loyalty_program.save
      current_business.update!(loyalty_program_enabled: true)
      redirect_to business_manager_loyalty_index_path, notice: 'Loyalty program created successfully.'
    else
      @loyalty_stats = {}
      @recent_transactions = []
      render :index, status: :unprocessable_entity
    end
  end
  
  def toggle_status
    if current_business.loyalty_program_enabled?
      # Check if any services use loyalty fallback before disabling
      services_with_loyalty_fallback = current_business.services.where(
        subscription_enabled: true,
        subscription_rebooking_preference: 'same_day_loyalty_fallback'
      )
      
      if services_with_loyalty_fallback.exists?
        # Show warning and auto-convert
        service_names = services_with_loyalty_fallback.pluck(:name).join(', ')
        current_business.update!(loyalty_program_enabled: false)
        message = "Loyalty program disabled. The following services with loyalty fallback were automatically converted to standard rebooking: #{service_names}."
      else
        current_business.update!(loyalty_program_enabled: false)
        message = 'Loyalty program disabled.'
      end
    else
      current_business.update!(loyalty_program_enabled: true)
      ensure_loyalty_program!
      message = 'Loyalty program enabled.'
    end
    
    redirect_to business_manager_loyalty_index_path, notice: message
  end
  
  def customers
    # Get customers with positive loyalty point balances
    # Using a separate query to avoid GROUP BY conflicts with includes
    customer_points_data = current_business.tenant_customers
                                         .joins(:loyalty_transactions)
                                         .group('tenant_customers.id')
                                         .having('SUM(loyalty_transactions.points_amount) > 0')
                                         .pluck('tenant_customers.id', 'SUM(loyalty_transactions.points_amount)')
                                         .to_h
    
    customer_ids_with_points = customer_points_data.keys
    
    @customers_with_points = current_business.tenant_customers
                                           .where(id: customer_ids_with_points)
                                           .page(params[:page])
    
    # Create a hash to lookup points by customer ID for the view
    @customer_points = customer_points_data
    
    # Precompute last transaction for each customer to avoid N+1 queries
    @last_transactions = {}
    if customer_ids_with_points.any?
      # Get the latest transaction for each customer
      latest_transactions = current_business.loyalty_transactions
                                          .where(tenant_customer_id: customer_ids_with_points)
                                          .select('DISTINCT ON (tenant_customer_id) tenant_customer_id, transaction_type, created_at')
                                          .order('tenant_customer_id, created_at DESC')
      
      latest_transactions.each do |transaction|
        @last_transactions[transaction.tenant_customer_id] = transaction
      end
    end
    
    @customer_stats = calculate_customer_loyalty_stats
  end
  
  def customer_detail
    @customer = current_business.tenant_customers.find(params[:id])
    @loyalty_summary = LoyaltyPointsService.get_customer_summary(@customer)
    @loyalty_history = @customer.loyalty_points_history
    @redemption_options = LoyaltyPointsService.get_redemption_options(@customer)
  end
  
  def adjust_points
    @customer = current_business.tenant_customers.find(params[:customer_id])
    points = params[:points].to_i
    description = params[:description].presence || "Manual adjustment by #{current_user.full_name}"
    
    if points != 0
      LoyaltyPointsService.award_points(
        customer: @customer,
        points: points,
        description: description
      )
      
      redirect_to customer_detail_business_manager_loyalty_path(@customer), 
                  notice: "#{points > 0 ? 'Added' : 'Deducted'} #{points.abs} points successfully."
    else
      redirect_to customer_detail_business_manager_loyalty_path(@customer), 
                  alert: 'Invalid points amount.'
    end
  end
  
  def analytics
    @date_range = params[:date_range] || '30_days'
    @analytics = calculate_detailed_analytics(@date_range)
    @engagement_rate = @analytics[:engagement_rate]
    @top_earners = @analytics[:top_earners]
    
    respond_to do |format|
      format.html
      format.json { render json: @analytics }
    end
  end
  
  private
  
  def set_loyalty_program
    @loyalty_program = current_business.loyalty_programs.first
    redirect_to business_manager_loyalty_index_path, alert: 'Please create a loyalty program first.' unless @loyalty_program
  end
  
  def loyalty_program_params
    params.require(:loyalty_program).permit(
      :name, :points_name, :points_for_booking, :points_for_referral, 
      :points_per_dollar, :active
    )
  end
  
  def calculate_loyalty_stats
    transactions = current_business.loyalty_transactions
    customers = current_business.tenant_customers.joins(:loyalty_transactions).distinct
    
    {
      total_customers: customers.count,
      total_points_issued: transactions.earned.sum(:points_amount),
      total_points_redeemed: transactions.redeemed.sum(:points_amount).abs,
      active_customers: customers.joins(:loyalty_transactions)
                                .where(loyalty_transactions: { created_at: 30.days.ago.. })
                                .distinct.count,
      average_points_per_customer: customers.count > 0 ? 
        (transactions.sum(:points_amount) / customers.count.to_f).round(2) : 0,
      redemption_rate: calculate_redemption_rate,
      top_customers: get_top_loyalty_customers
    }
  end
  
  def calculate_customer_loyalty_stats
    customers = current_business.tenant_customers.joins(:loyalty_transactions)
    
    {
      total_with_points: customers.group('tenant_customers.id')
                                 .having('SUM(loyalty_transactions.points_amount) > 0')
                                 .count.size,
      average_balance: customers.group('tenant_customers.id')
                               .sum('loyalty_transactions.points_amount')
                               .values.sum / [customers.distinct.count, 1].max,
      highest_balance: customers.group('tenant_customers.id')
                               .sum('loyalty_transactions.points_amount')
                               .values.max || 0
    }
  end
  
  def calculate_redemption_rate
    total_earned = current_business.loyalty_transactions.earned.sum(:points_amount)
    return 0 if total_earned.zero?
    
    total_redeemed = current_business.loyalty_transactions.redeemed.sum(:points_amount).abs
    (total_redeemed.to_f / total_earned * 100).round(2)
  end
  
  def get_top_loyalty_customers
    current_business.tenant_customers
                   .joins(:loyalty_transactions)
                   .group('tenant_customers.id, tenant_customers.first_name, tenant_customers.last_name, tenant_customers.email')
                   .order('SUM(loyalty_transactions.points_amount) DESC')
                   .limit(5)
                   .pluck('tenant_customers.first_name', 'tenant_customers.last_name', 'tenant_customers.email', 'SUM(loyalty_transactions.points_amount)')
                   .map { |first_name, last_name, email, points| { name: "#{first_name} #{last_name}".strip, email: email, points: points } }
  end
  
  def ensure_loyalty_program!
    return if current_business.loyalty_programs.exists?
    
    current_business.loyalty_programs.create!(
      name: "#{current_business.name} Loyalty Program",
      points_name: 'points',
      points_for_booking: 10,
      points_for_referral: 100,
                  points_per_dollar: 1,
      active: true
    )
  end
  
  def calculate_detailed_analytics(date_range)
    start_date = case date_range
                when '7_days' then 7.days.ago
                when '30_days' then 30.days.ago
                when '90_days' then 90.days.ago
                when '1_year' then 1.year.ago
                else 30.days.ago
                end
    
    transactions = current_business.loyalty_transactions.where(created_at: start_date..)
    
    {
      period: date_range,
      total_points_earned: transactions.earned.sum(:points_amount),
      total_points_redeemed: transactions.redeemed.sum(:points_amount).abs,
      active_users: transactions.joins(:tenant_customer).distinct.count('tenant_customers.id'),
      engagement_rate: calculate_engagement_rate(transactions),
      daily_breakdown: calculate_daily_points_breakdown(transactions, start_date),
      top_earners: calculate_top_point_earners(transactions),
      redemption_trends: calculate_redemption_trends(transactions)
    }
  end
  
  def calculate_engagement_rate(transactions)
    total_customers = current_business.tenant_customers.count
    return 0 if total_customers.zero?
    
    active_customers = transactions.joins(:tenant_customer).distinct.count('tenant_customers.id')
    (active_customers.to_f / total_customers * 100).round(2)
  end
  
  def calculate_daily_points_breakdown(transactions, start_date)
    (start_date.to_date..Date.current).map do |date|
      day_transactions = transactions.where(created_at: date.beginning_of_day..date.end_of_day)
      {
        date: date,
        earned: day_transactions.earned.sum(:points_amount),
        redeemed: day_transactions.redeemed.sum(:points_amount).abs
      }
    end
  end
  
  def calculate_top_point_earners(transactions)
    transactions.earned
               .joins(:tenant_customer)
               .group('tenant_customers.id, tenant_customers.first_name, tenant_customers.last_name, tenant_customers.email')
               .order('SUM(loyalty_transactions.points_amount) DESC')
               .limit(10)
               .pluck('tenant_customers.first_name', 'tenant_customers.last_name', 'tenant_customers.email', 'SUM(loyalty_transactions.points_amount)')
               .map.with_index(1) do |(first_name, last_name, email, points), rank|
                 { rank: rank, name: "#{first_name} #{last_name}".strip, email: email, points: points }
               end
  end
  
  def calculate_redemption_trends(transactions)
    redemptions = transactions.redeemed.group_by_day(:created_at).sum(:points_amount)
    redemptions.transform_values(&:abs)
  end
end 