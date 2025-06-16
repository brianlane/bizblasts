# frozen_string_literal: true

class SubscriptionLoyaltyService
  attr_reader :customer_subscription, :business, :tenant_customer

  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
  end

  # Award loyalty points for successful subscription payments
  def award_subscription_payment_points!
    return 0 unless business.loyalty_program_enabled?
    return 0 unless customer_subscription.active?

    # Check if points already awarded for this billing cycle
    existing_transaction = LoyaltyTransaction.where(
      tenant_customer: tenant_customer,
      business: business,
      description: subscription_payment_description
    ).where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).first

    return 0 if existing_transaction

    points = calculate_subscription_payment_points
    return 0 unless points > 0

    LoyaltyPointsService.award_points(
      customer: tenant_customer,
      points: points,
      description: subscription_payment_description,
      related_record: customer_subscription
    )
  end

  # Award bonus loyalty points for subscription milestones
  def award_milestone_points!(milestone_type)
    return 0 unless business.loyalty_program_enabled?
    return 0 unless customer_subscription.active?

    points = calculate_milestone_points(milestone_type)
    return 0 unless points > 0

    description = milestone_description(milestone_type)

    LoyaltyPointsService.award_points(
      customer: tenant_customer,
      points: points,
      description: description,
      related_record: customer_subscription
    )
  end

  # Award loyalty points as compensation (for out-of-stock, rebooking issues, etc.)
  def award_compensation_points!(reason)
    return 0 unless business.loyalty_program_enabled?

    points = calculate_compensation_points(reason)
    return 0 unless points > 0

    description = compensation_description(reason)

    LoyaltyPointsService.award_points(
      customer: tenant_customer,
      points: points,
      description: description,
      related_record: customer_subscription
    )
  end

  # Calculate subscription loyalty tier benefits
  def calculate_tier_benefits
    return {} unless business.loyalty_program_enabled?

    subscription_count = tenant_customer.customer_subscriptions.active.count
    total_subscription_value = tenant_customer.customer_subscriptions.active.sum(:subscription_price)
    subscription_duration_months = calculate_average_subscription_duration

    tier = determine_subscription_loyalty_tier(subscription_count, total_subscription_value, subscription_duration_months)
    
    {
      tier: tier,
      tier_name: tier_name(tier),
      benefits: tier_benefits(tier),
      next_tier: next_tier(tier),
      progress_to_next_tier: calculate_tier_progress(tier, subscription_count, total_subscription_value)
    }
  end

  # Apply subscription loyalty discounts
  def apply_subscription_loyalty_discount
    return { success: false, error: 'Loyalty program not enabled' } unless business.loyalty_program_enabled?

    tier_benefits = calculate_tier_benefits
    discount_percentage = tier_benefits[:benefits][:subscription_discount] || 0

    return { success: false, error: 'No loyalty discount available' } if discount_percentage.zero?

    discount_amount = (customer_subscription.original_price * discount_percentage / 100).round(2)

    {
      success: true,
      discount_percentage: discount_percentage,
      discount_amount: discount_amount,
      tier: tier_benefits[:tier_name]
    }
  end

  # Get subscription loyalty summary for customer
  def get_subscription_loyalty_summary
    return {} unless business.loyalty_program_enabled?

    {
      subscription_points_earned: calculate_total_subscription_points_earned,
      subscription_milestones_achieved: get_achieved_milestones,
      tier_benefits: calculate_tier_benefits,
      upcoming_rewards: calculate_upcoming_rewards,
      loyalty_subscription_history: get_loyalty_subscription_history
    }
  end

  # Check if customer qualifies for loyalty-based subscription perks
  def qualifies_for_loyalty_perks?
    return false unless business.loyalty_program_enabled?
    
    tier_benefits = calculate_tier_benefits
    tier_benefits[:tier] >= 2 # Bronze tier or higher
  end

  # Get available loyalty redemption options for subscriptions
  def get_subscription_redemption_options
    return [] unless business.loyalty_program_enabled?

    current_points = tenant_customer.current_loyalty_points
    options = []

    # Subscription discount options
    [
      { points: 500, discount: 5, description: "5% off next subscription payment" },
      { points: 1000, discount: 10, description: "10% off next subscription payment" },
      { points: 2000, discount: 20, description: "20% off next subscription payment" },
      { points: 5000, discount: 50, description: "50% off next subscription payment" }
    ].each do |option|
      if current_points >= option[:points]
        options << {
          points_required: option[:points],
          benefit_type: 'subscription_discount',
          benefit_value: option[:discount],
          description: option[:description],
          available: true
        }
      end
    end

    # Free month options
    if current_points >= 3000
      options << {
        points_required: 3000,
        benefit_type: 'free_month',
        benefit_value: 1,
        description: "Skip one month's payment (subscription continues)",
        available: true
      }
    end

    # Upgrade options (for product subscriptions)
    if customer_subscription.product_subscription? && current_points >= 1500
      options << {
        points_required: 1500,
        benefit_type: 'upgrade_variant',
        benefit_value: 1,
        description: "Upgrade to premium variant for one delivery",
        available: true
      }
    end

    options
  end

  # Redeem loyalty points for subscription benefits
  def redeem_points_for_subscription_benefit(points, benefit_type, benefit_value)
    return { success: false, error: 'Loyalty program not enabled' } unless business.loyalty_program_enabled?
    return { success: false, error: 'Insufficient points' } unless tenant_customer.can_redeem_points?(points)

    begin
      ActiveRecord::Base.transaction do
        # Create redemption transaction
        tenant_customer.loyalty_transactions.create!(
          business: business,
          transaction_type: 'redeemed',
          points_amount: -points,
          description: "Redeemed #{points} points for subscription #{benefit_type}"
        )

        # Apply the benefit
        case benefit_type
        when 'subscription_discount'
          apply_points_discount(benefit_value)
        when 'free_month'
          apply_free_month
        when 'upgrade_variant'
          apply_variant_upgrade
        end

        {
          success: true,
          benefit_applied: benefit_type,
          points_redeemed: points,
          description: "Successfully redeemed #{points} points for #{benefit_type}"
        }
      end
    rescue => e
      { success: false, error: "Error redeeming points: #{e.message}" }
    end
  end

  private

  def calculate_subscription_payment_points
    base_points = business.loyalty_programs.first&.points_for_booking || 10
    dollar_points = (customer_subscription.subscription_price * (business.loyalty_programs.first&.points_per_dollar || 1)).to_i
    
    # Subscription bonus multiplier
    subscription_multiplier = calculate_subscription_multiplier
    
    (base_points + dollar_points) * subscription_multiplier
  end

  def calculate_subscription_multiplier
    # Longer subscriptions get bonus points
    months_active = ((Time.current - customer_subscription.created_at) / 1.month).to_i
    
    case months_active
    when 0..2 then 1.0
    when 3..5 then 1.2
    when 6..11 then 1.5
    when 12..23 then 2.0
    else 2.5
    end
  end

  def calculate_milestone_points(milestone_type)
    case milestone_type
    when 'first_month' then 100
    when 'three_months' then 250
    when 'six_months' then 500
    when 'one_year' then 1000
    when 'two_years' then 2000
    when 'loyalty_tier_upgrade' then 300
    else 0
    end
  end

  def calculate_compensation_points(reason)
    base_compensation = (customer_subscription.subscription_price * 0.5).to_i # 50% of subscription value
    
    case reason
    when 'out_of_stock' then base_compensation
    when 'booking_unavailable' then base_compensation
    when 'service_cancelled' then base_compensation * 1.5
    when 'quality_issue' then base_compensation * 2
    else base_compensation
    end
  end

  def determine_subscription_loyalty_tier(subscription_count, total_value, duration_months)
    # Tier calculation based on multiple factors
    score = 0
    score += subscription_count * 10
    score += (total_value / 10).to_i
    score += duration_months * 5

    case score
    when 0..49 then 1    # Basic
    when 50..149 then 2  # Bronze
    when 150..299 then 3 # Silver
    when 300..499 then 4 # Gold
    else 5               # Platinum
    end
  end

  def tier_name(tier)
    %w[Basic Bronze Silver Gold Platinum][tier - 1] || 'Basic'
  end

  def tier_benefits(tier)
    case tier
    when 1 # Basic
      { subscription_discount: 0, bonus_points_multiplier: 1.0, priority_support: false }
    when 2 # Bronze
      { subscription_discount: 5, bonus_points_multiplier: 1.2, priority_support: false }
    when 3 # Silver
      { subscription_discount: 10, bonus_points_multiplier: 1.5, priority_support: true }
    when 4 # Gold
      { subscription_discount: 15, bonus_points_multiplier: 2.0, priority_support: true }
    when 5 # Platinum
      { subscription_discount: 20, bonus_points_multiplier: 2.5, priority_support: true }
    else
      { subscription_discount: 0, bonus_points_multiplier: 1.0, priority_support: false }
    end
  end

  def next_tier(current_tier)
    current_tier < 5 ? current_tier + 1 : nil
  end

  def calculate_tier_progress(current_tier, subscription_count, total_value)
    return nil if current_tier >= 5

    current_score = subscription_count * 10 + (total_value / 10).to_i
    next_tier_threshold = case current_tier
                         when 1 then 50
                         when 2 then 150
                         when 3 then 300
                         when 4 then 500
                         end

    return nil unless next_tier_threshold

    progress_percentage = [(current_score.to_f / next_tier_threshold * 100).round(1), 100.0].min
    
    {
      current_score: current_score,
      required_score: next_tier_threshold,
      progress_percentage: progress_percentage,
      points_needed: [next_tier_threshold - current_score, 0].max
    }
  end

  def calculate_average_subscription_duration
    subscriptions = tenant_customer.customer_subscriptions
    return 0 if subscriptions.empty?

    total_months = subscriptions.sum do |sub|
      start_date = sub.created_at
      end_date = sub.cancelled_at || Time.current
      ((end_date - start_date) / 1.month).to_i
    end

    (total_months.to_f / subscriptions.count).round(1)
  end

  def calculate_total_subscription_points_earned
    tenant_customer.loyalty_transactions
                   .where(description: [subscription_payment_description, /Subscription.*milestone/, /Subscription.*compensation/])
                   .sum(:points_amount)
  end

  def get_achieved_milestones
    milestones = []
    months_active = ((Time.current - customer_subscription.created_at) / 1.month).to_i

    milestones << 'first_month' if months_active >= 1
    milestones << 'three_months' if months_active >= 3
    milestones << 'six_months' if months_active >= 6
    milestones << 'one_year' if months_active >= 12
    milestones << 'two_years' if months_active >= 24

    milestones
  end

  def calculate_upcoming_rewards
    upcoming = []
    months_active = ((Time.current - customer_subscription.created_at) / 1.month).to_i

    if months_active < 3
      upcoming << { milestone: 'three_months', months_remaining: 3 - months_active, points: 250 }
    elsif months_active < 6
      upcoming << { milestone: 'six_months', months_remaining: 6 - months_active, points: 500 }
    elsif months_active < 12
      upcoming << { milestone: 'one_year', months_remaining: 12 - months_active, points: 1000 }
    elsif months_active < 24
      upcoming << { milestone: 'two_years', months_remaining: 24 - months_active, points: 2000 }
    end

    upcoming
  end

  def get_loyalty_subscription_history
    tenant_customer.loyalty_transactions
                   .where(description: [subscription_payment_description, /Subscription.*milestone/, /Subscription.*compensation/])
                   .order(created_at: :desc)
                   .limit(20)
  end

  def subscription_payment_description
    "Subscription payment points for #{customer_subscription.item_name}"
  end

  def milestone_description(milestone_type)
    case milestone_type
    when 'first_month' then "First month subscription milestone for #{customer_subscription.item_name}"
    when 'three_months' then "Three month subscription milestone for #{customer_subscription.item_name}"
    when 'six_months' then "Six month subscription milestone for #{customer_subscription.item_name}"
    when 'one_year' then "One year subscription milestone for #{customer_subscription.item_name}"
    when 'two_years' then "Two year subscription milestone for #{customer_subscription.item_name}"
    when 'loyalty_tier_upgrade' then "Loyalty tier upgrade bonus for #{customer_subscription.item_name}"
    else "Subscription milestone for #{customer_subscription.item_name}"
    end
  end

  def compensation_description(reason)
    case reason
    when 'out_of_stock' then "Compensation points for out-of-stock #{customer_subscription.item_name}"
    when 'booking_unavailable' then "Compensation points for unavailable booking #{customer_subscription.item_name}"
    when 'service_cancelled' then "Compensation points for cancelled service #{customer_subscription.item_name}"
    when 'quality_issue' then "Compensation points for quality issue #{customer_subscription.item_name}"
    else "Subscription compensation points for #{customer_subscription.item_name}"
    end
  end

  def apply_points_discount(discount_percentage)
    # This would integrate with the subscription billing system
    # For now, we'll create a record of the discount to be applied
    customer_subscription.subscription_transactions.create!(
      business: business,
      tenant_customer: tenant_customer,
      transaction_type: 'discount_applied',
      status: 'completed',
      amount: -(customer_subscription.subscription_price * discount_percentage / 100),
      notes: "#{discount_percentage}% loyalty points discount applied"
    )
  end

  def apply_free_month
    # Skip the next billing cycle
    customer_subscription.update!(
      next_billing_date: customer_subscription.next_billing_date + 1.month
    )
    
    customer_subscription.subscription_transactions.create!(
      business: business,
      tenant_customer: tenant_customer,
      transaction_type: 'free_month_applied',
      status: 'completed',
      amount: 0,
      notes: "Free month applied via loyalty points redemption"
    )
  end

  def apply_variant_upgrade
    # This would upgrade the product variant for the next delivery
    # Implementation would depend on the specific business logic
    customer_subscription.subscription_transactions.create!(
      business: business,
      tenant_customer: tenant_customer,
      transaction_type: 'variant_upgrade_applied',
      status: 'completed',
      amount: 0,
      notes: "Product variant upgrade applied via loyalty points redemption"
    )
  end
end 
 
 
 
 