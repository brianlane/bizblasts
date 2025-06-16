# frozen_string_literal: true

class BusinessManager::SubscriptionLoyaltyController < BusinessManager::BaseController
  before_action :ensure_loyalty_program_enabled
  before_action :set_customer_subscription, only: [:show, :award_points, :adjust_tier]

  def index
    @subscription_loyalty_stats = calculate_subscription_loyalty_stats
    @top_subscription_customers = get_top_subscription_loyalty_customers
    @recent_subscription_activity = get_recent_subscription_loyalty_activity
    @tier_distribution = calculate_tier_distribution
  end

  def customers
    @q = current_business.tenant_customers
                        .joins(:customer_subscriptions)
                        .where(customer_subscriptions: { status: 'active' })
                        .distinct
                        .ransack(params[:q])
    
    @customers = @q.result.includes(:customer_subscriptions, :loyalty_transactions)
                   .page(params[:page])
                   .per(20)
  end

  def show
    @loyalty_summary = @customer_subscription.loyalty_summary
    @tier_benefits = @customer_subscription.loyalty_tier_benefits
    @loyalty_history = get_subscription_loyalty_history
    @available_actions = get_available_loyalty_actions
  end

  def award_points
    points = params[:points].to_i
    reason = params[:reason].presence || "Manual points award by #{current_user.full_name}"

    if points > 0
      loyalty_service = SubscriptionLoyaltyService.new(@customer_subscription)
      awarded_points = loyalty_service.award_compensation_points!(reason)
      
      redirect_to business_manager_subscription_loyalty_path(@customer_subscription),
                  notice: "Successfully awarded #{awarded_points} loyalty points."
    else
      redirect_to business_manager_subscription_loyalty_path(@customer_subscription),
                  alert: "Invalid points amount."
    end
  end

  def adjust_tier
    # This would be used for manual tier adjustments if needed
    # Implementation depends on business requirements
    redirect_to business_manager_subscription_loyalty_path(@customer_subscription),
                notice: "Tier adjustment feature coming soon."
  end

  def analytics
    @date_range = params[:date_range] || '30_days'
    @analytics = calculate_subscription_loyalty_analytics(@date_range)
    
    respond_to do |format|
      format.html
      format.json { render json: @analytics }
    end
  end

  def export_data
    @customers = current_business.tenant_customers
                                .joins(:customer_subscriptions)
                                .where(customer_subscriptions: { status: 'active' })
                                .includes(:customer_subscriptions, :loyalty_transactions)

    respond_to do |format|
      format.csv do
        csv_data = generate_subscription_loyalty_csv
        send_data csv_data, filename: "subscription_loyalty_data_#{Date.current}.csv"
      end
    end
  end

  private

  def ensure_loyalty_program_enabled
    unless current_business.loyalty_program_enabled?
      redirect_to business_manager_dashboard_path, 
                  alert: 'Loyalty program must be enabled to access subscription loyalty features.'
    end
  end

  def set_customer_subscription
    @customer_subscription = current_business.customer_subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_subscription_loyalty_index_path, 
                alert: 'Subscription not found.'
  end

  def calculate_subscription_loyalty_stats
    active_subscriptions = current_business.customer_subscriptions.active
    
    {
      total_active_subscriptions: active_subscriptions.count,
      subscriptions_with_loyalty: active_subscriptions.joins(:tenant_customer)
                                                     .joins('JOIN loyalty_transactions ON loyalty_transactions.tenant_customer_id = tenant_customers.id')
                                                     .distinct.count,
      total_subscription_points_awarded: calculate_total_subscription_points,
      average_points_per_subscription: calculate_average_points_per_subscription,
      top_tier_customers: count_customers_by_tier(4..5), # Gold and Platinum
      loyalty_engagement_rate: calculate_loyalty_engagement_rate
    }
  end

  def get_top_subscription_loyalty_customers
    current_business.tenant_customers
                   .joins(:customer_subscriptions, :loyalty_transactions)
                   .where(customer_subscriptions: { status: 'active' })
                   .where('loyalty_transactions.description LIKE ?', '%Subscription%')
                   .group('tenant_customers.id, tenant_customers.name, tenant_customers.email')
                   .order('SUM(loyalty_transactions.points_amount) DESC')
                   .limit(10)
                   .pluck('tenant_customers.id', 'tenant_customers.name', 'tenant_customers.email', 'SUM(loyalty_transactions.points_amount)')
                   .map do |id, name, email, points|
                     customer = current_business.tenant_customers.find(id)
                     subscription = customer.customer_subscriptions.active.first
                     tier_info = subscription ? SubscriptionLoyaltyService.new(subscription).calculate_tier_benefits : {}
                     
                     {
                       customer_id: id,
                       name: name,
                       email: email,
                       subscription_points: points,
                       tier: tier_info[:tier_name] || 'Basic',
                       active_subscriptions: customer.customer_subscriptions.active.count
                     }
                   end
  end

  def get_recent_subscription_loyalty_activity
    current_business.loyalty_transactions
                   .where('description LIKE ?', '%Subscription%')
                   .includes(:tenant_customer)
                   .order(created_at: :desc)
                   .limit(20)
                   .map do |transaction|
                     {
                       customer_name: transaction.tenant_customer.name,
                       customer_email: transaction.tenant_customer.email,
                       points: transaction.points_amount,
                       description: transaction.description,
                       created_at: transaction.created_at,
                       transaction_type: transaction.transaction_type
                     }
                   end
  end

  def calculate_tier_distribution
    tier_counts = { 'Basic' => 0, 'Bronze' => 0, 'Silver' => 0, 'Gold' => 0, 'Platinum' => 0 }
    
    current_business.customer_subscriptions.active.includes(:tenant_customer).each do |subscription|
      tier_info = SubscriptionLoyaltyService.new(subscription).calculate_tier_benefits
      tier_name = tier_info[:tier_name] || 'Basic'
      tier_counts[tier_name] += 1
    end
    
    tier_counts
  end

  def get_subscription_loyalty_history
    loyalty_service = SubscriptionLoyaltyService.new(@customer_subscription)
    loyalty_service.send(:get_loyalty_subscription_history)
  end

  def get_available_loyalty_actions
    [
      { action: 'award_compensation', label: 'Award Compensation Points', description: 'Award points for service issues' },
      { action: 'award_milestone', label: 'Award Milestone Bonus', description: 'Manually award milestone points' },
      { action: 'adjust_tier', label: 'Adjust Tier', description: 'Manually adjust customer tier' }
    ]
  end

  def calculate_subscription_loyalty_analytics(date_range)
    start_date = case date_range
                when '7_days' then 7.days.ago
                when '30_days' then 30.days.ago
                when '90_days' then 90.days.ago
                when '1_year' then 1.year.ago
                else 30.days.ago
                end

    subscription_transactions = current_business.loyalty_transactions
                                              .where('description LIKE ?', '%Subscription%')
                                              .where(created_at: start_date..)

    {
      period: date_range,
      total_subscription_points_awarded: subscription_transactions.where(transaction_type: 'earned').sum(:points_amount),
      total_subscription_points_redeemed: subscription_transactions.where(transaction_type: 'redeemed').sum(:points_amount).abs,
      unique_subscription_customers: subscription_transactions.distinct.count(:tenant_customer_id),
      milestone_achievements: count_milestone_achievements(subscription_transactions),
      compensation_points_awarded: count_compensation_points(subscription_transactions),
      daily_breakdown: calculate_daily_subscription_points(subscription_transactions, start_date)
    }
  end

  def generate_subscription_loyalty_csv
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << ['Customer Name', 'Email', 'Active Subscriptions', 'Total Subscription Points', 'Current Tier', 'Tier Benefits', 'Last Activity']
      
      @customers.each do |customer|
        subscription = customer.customer_subscriptions.active.first
        next unless subscription
        
        loyalty_service = SubscriptionLoyaltyService.new(subscription)
        tier_info = loyalty_service.calculate_tier_benefits
        subscription_points = loyalty_service.send(:calculate_total_subscription_points_earned)
        
        csv << [
          customer.name,
          customer.email,
          customer.customer_subscriptions.active.count,
          subscription_points,
          tier_info[:tier_name] || 'Basic',
          "#{tier_info.dig(:benefits, :subscription_discount) || 0}% discount, #{tier_info.dig(:benefits, :bonus_points_multiplier) || 1}x points",
          customer.loyalty_transactions.order(:created_at).last&.created_at&.strftime('%m/%d/%Y')
        ]
      end
    end
  end

  def calculate_total_subscription_points
    current_business.loyalty_transactions
                   .where('description LIKE ?', '%Subscription%')
                   .where(transaction_type: 'earned')
                   .sum(:points_amount)
  end

  def calculate_average_points_per_subscription
    active_count = current_business.customer_subscriptions.active.count
    return 0 if active_count.zero?
    
    calculate_total_subscription_points / active_count
  end

  def count_customers_by_tier(tier_range)
    count = 0
    current_business.customer_subscriptions.active.includes(:tenant_customer).each do |subscription|
      tier_info = SubscriptionLoyaltyService.new(subscription).calculate_tier_benefits
      count += 1 if tier_range.include?(tier_info[:tier] || 1)
    end
    count
  end

  def calculate_loyalty_engagement_rate
    total_subscriptions = current_business.customer_subscriptions.active.count
    return 0 if total_subscriptions.zero?
    
    engaged_subscriptions = current_business.customer_subscriptions.active
                                           .joins(:tenant_customer)
                                           .joins('JOIN loyalty_transactions ON loyalty_transactions.tenant_customer_id = tenant_customers.id')
                                           .where('loyalty_transactions.description LIKE ?', '%Subscription%')
                                           .distinct.count
    
    (engaged_subscriptions.to_f / total_subscriptions * 100).round(1)
  end

  def count_milestone_achievements(transactions)
    transactions.where('description LIKE ?', '%milestone%').count
  end

  def count_compensation_points(transactions)
    transactions.where('description LIKE ?', '%Compensation%').sum(:points_amount)
  end

  def calculate_daily_subscription_points(transactions, start_date)
    daily_data = {}
    (start_date.to_date..Date.current).each { |date| daily_data[date] = 0 }
    
    transactions.group('DATE(created_at)').sum(:points_amount).each do |date, points|
      daily_data[date] = points if daily_data.key?(date)
    end
    
    daily_data.map { |date, points| { date: date, points: points } }
  end
end 
 
