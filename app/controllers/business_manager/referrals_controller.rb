class BusinessManager::ReferralsController < BusinessManager::BaseController
  before_action :set_referral_program, only: [:show, :edit, :update]
  
  def index
    @referral_program = current_business.referral_program || current_business.build_referral_program
    @referrals = current_business.referrals.includes(:referrer, :referred_tenant_customer).recent.limit(20)
    @referral_stats = calculate_referral_stats
  end
  
  def show
    @referrals = current_business.referrals.includes(:referrer, :referred_tenant_customer).recent.page(params[:page])
    @referral_stats = calculate_referral_stats
  end
  
  def edit
  end
  
  def update
    if @referral_program.update(referral_program_params)
      # Enable referral program on business if activating
      if @referral_program.active? && !current_business.referral_program_enabled?
        current_business.update!(referral_program_enabled: true)
      end
      
      redirect_to business_manager_referrals_path, notice: 'Referral program updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def create
    @referral_program = current_business.build_referral_program(referral_program_params.merge(referrer_reward_type: 'points'))
    
    if @referral_program.save
      current_business.update!(referral_program_enabled: true)
      redirect_to business_manager_referrals_path, notice: 'Referral program created successfully.'
    else
      @referrals = []
      @referral_stats = {}
      render :index, status: :unprocessable_entity
    end
  end
  
  def toggle_status
    if current_business.referral_program_enabled?
      current_business.update!(referral_program_enabled: false)
      message = 'Referral program disabled.'
    else
      current_business.update!(referral_program_enabled: true)
      current_business.ensure_referral_program!
      message = 'Referral program enabled.'
    end
    
    redirect_to business_manager_referrals_path, notice: message
  end
  
  def analytics
    @date_range = params[:date_range] || '30_days'
    @referral_analytics = calculate_detailed_analytics(@date_range)
    
    respond_to do |format|
      format.html
      format.json { render json: @referral_analytics }
    end
  end
  
  private
  
  def set_referral_program
    @referral_program = current_business.referral_program || current_business.build_referral_program
  end
  
  def referral_program_params
    params.require(:referral_program).permit(
      :active, :referrer_reward_value, :referral_code_discount_amount, :min_purchase_amount
    )
  end
  
  def calculate_referral_stats
    referrals = current_business.referrals
    
    {
      total_referrals: referrals.count,
      pending_referrals: referrals.pending.count,
      qualified_referrals: referrals.qualified.count,
      rewarded_referrals: referrals.rewarded.count,
      total_revenue_from_referrals: calculate_referral_revenue,
      top_referrers: get_top_referrers,
      recent_activity: get_recent_referral_activity
    }
  end
  
  def calculate_referral_revenue
    current_business.referrals.qualified.joins(:qualifying_booking, :qualifying_order)
      .sum(Arel.sql('COALESCE(bookings.amount, 0) + COALESCE(orders.total_amount, 0)'))
  end
  
  def get_top_referrers
    current_business.referrals.qualified
      .joins(:referrer)
      .group('users.id, users.first_name, users.last_name, users.email')
      .order(Arel.sql('COUNT(*) DESC'))
      .limit(5)
      .pluck('users.first_name', 'users.last_name', 'users.email', Arel.sql('COUNT(*)'))
      .map { |first, last, email, count| { name: "#{first} #{last}", email: email, referrals: count } }
  end
  
  def get_recent_referral_activity
    current_business.referrals.includes(:referrer, :referred_tenant_customer)
      .order(created_at: :desc)
      .limit(10)
      .map do |referral|
        {
          referrer_name: referral.referrer.full_name,
          referred_name: referral.referred_tenant_customer&.name || 'Pending',
          status: referral.status,
          created_at: referral.created_at,
          qualified_at: referral.qualification_met_at
        }
      end
  end
  
  def calculate_detailed_analytics(date_range)
    start_date = case date_range
                when '7_days' then 7.days.ago
                when '30_days' then 30.days.ago
                when '90_days' then 90.days.ago
                when '1_year' then 1.year.ago
                else 30.days.ago
                end
    
    referrals = current_business.referrals.where(created_at: start_date..)
    
    {
      period: date_range,
      total_referrals: referrals.count,
      conversion_rate: calculate_conversion_rate(referrals),
      revenue_impact: calculate_revenue_impact(referrals),
      daily_breakdown: calculate_daily_breakdown(referrals, start_date),
      referrer_leaderboard: calculate_referrer_leaderboard(referrals)
    }
  end
  
  def calculate_conversion_rate(referrals)
    total = referrals.count
    return 0 if total.zero?
    
    qualified = referrals.qualified.count
    (qualified.to_f / total * 100).round(2)
  end
  
  def calculate_revenue_impact(referrals)
    qualified_referrals = referrals.qualified
    
    booking_revenue = qualified_referrals.joins(:qualifying_booking).sum(Arel.sql('bookings.amount'))
    order_revenue = qualified_referrals.joins(:qualifying_order).sum(Arel.sql('orders.total_amount'))
    
    booking_revenue + order_revenue
  end
  
  def calculate_daily_breakdown(referrals, start_date)
    (start_date.to_date..Date.current).map do |date|
      day_referrals = referrals.where(created_at: date.beginning_of_day..date.end_of_day)
      {
        date: date,
        referrals: day_referrals.count,
        qualified: day_referrals.qualified.count
      }
    end
  end
  
  def calculate_referrer_leaderboard(referrals)
    referrals.joins(:referrer)
      .group('users.id, users.first_name, users.last_name, users.email')
      .order(Arel.sql('COUNT(*) DESC'))
      .limit(10)
      .pluck('users.first_name', 'users.last_name', 'users.email', Arel.sql('COUNT(*)'))
      .map.with_index(1) do |(first, last, email, count), rank|
        {
          rank: rank,
          name: "#{first} #{last}",
          email: email,
          total_referrals: count,
          qualified_referrals: referrals.qualified.joins(:referrer).where(users: { email: email }).count
        }
      end
  end
end 