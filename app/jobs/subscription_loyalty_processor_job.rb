# frozen_string_literal: true

class SubscriptionLoyaltyProcessorJob < ApplicationJob
  queue_as :default

  def perform(customer_subscription_id)
    customer_subscription = CustomerSubscription.find(customer_subscription_id)
    return unless customer_subscription.active?
    return unless customer_subscription.business.loyalty_program_enabled?

    Rails.logger.info "[SUBSCRIPTION LOYALTY JOB] Processing loyalty for subscription #{customer_subscription_id}"

    loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)

    # Award subscription payment points
    points_awarded = loyalty_service.award_subscription_payment_points!
    Rails.logger.info "[SUBSCRIPTION LOYALTY JOB] Awarded #{points_awarded} payment points"

    # Check and award milestone points
    check_and_award_milestones(loyalty_service, customer_subscription)

    # Check for tier upgrades and apply benefits
    check_tier_upgrades(loyalty_service, customer_subscription)

    # Send loyalty notifications if significant milestones achieved
    send_loyalty_notifications(customer_subscription, points_awarded)

    Rails.logger.info "[SUBSCRIPTION LOYALTY JOB] Completed processing for subscription #{customer_subscription_id}"
  rescue => e
    Rails.logger.error "[SUBSCRIPTION LOYALTY JOB] Error processing subscription #{customer_subscription_id}: #{e.message}"
    raise e
  end

  private

  def check_and_award_milestones(loyalty_service, customer_subscription)
    months_active = ((Time.current - customer_subscription.created_at) / 1.month).to_i
    
    milestones_to_check = [
      { months: 1, type: 'first_month' },
      { months: 3, type: 'three_months' },
      { months: 6, type: 'six_months' },
      { months: 12, type: 'one_year' },
      { months: 24, type: 'two_years' }
    ]

    milestones_to_check.each do |milestone|
      if months_active >= milestone[:months] && !milestone_already_awarded?(customer_subscription, milestone[:type])
        points_awarded = loyalty_service.award_milestone_points!(milestone[:type])
        Rails.logger.info "[SUBSCRIPTION LOYALTY JOB] Awarded #{points_awarded} points for #{milestone[:type]} milestone"
        
        # Send milestone achievement notification
        send_milestone_notification(customer_subscription, milestone[:type], points_awarded)
      end
    end
  end

  def check_tier_upgrades(loyalty_service, customer_subscription)
    current_tier_info = loyalty_service.calculate_tier_benefits
    previous_tier = get_previous_tier(customer_subscription)
    
    if current_tier_info[:tier] > previous_tier
      # Customer has been upgraded to a new tier
      loyalty_service.award_milestone_points!('loyalty_tier_upgrade')
      update_customer_tier_record(customer_subscription, current_tier_info[:tier])
      
      Rails.logger.info "[SUBSCRIPTION LOYALTY JOB] Customer upgraded to #{current_tier_info[:tier_name]} tier"
      
      # Send tier upgrade notification
      send_tier_upgrade_notification(customer_subscription, current_tier_info)
      
      # Apply tier discount if available
      customer_subscription.apply_loyalty_tier_discount!
    end
  end

  def milestone_already_awarded?(customer_subscription, milestone_type)
    description_pattern = case milestone_type
                         when 'first_month' then /First month subscription milestone/
                         when 'three_months' then /Three month subscription milestone/
                         when 'six_months' then /Six month subscription milestone/
                         when 'one_year' then /One year subscription milestone/
                         when 'two_years' then /Two year subscription milestone/
                         end

    customer_subscription.tenant_customer.loyalty_transactions
                         .where(description: description_pattern)
                         .exists?
  end

  def get_previous_tier(customer_subscription)
    # This could be stored in a separate table or calculated from historical data
    # For now, we'll use a simple approach based on the customer's loyalty history
    
    # Check if there's a previous tier upgrade transaction
    tier_upgrade_transaction = customer_subscription.tenant_customer.loyalty_transactions
                                                   .where('description LIKE ?', '%tier upgrade%')
                                                   .order(:created_at)
                                                   .last

    if tier_upgrade_transaction
      # Extract tier from description or use a more sophisticated method
      return 1 # Default to Basic if we can't determine
    else
      return 1 # Basic tier
    end
  end

  def update_customer_tier_record(customer_subscription, new_tier)
    # This could update a customer tier tracking table
    # For now, we'll create a transaction record
    customer_subscription.subscription_transactions.create!(
      business: customer_subscription.business,
      tenant_customer: customer_subscription.tenant_customer,
      transaction_type: 'tier_upgrade',
      status: 'completed',
      amount: 0,
      notes: "Upgraded to tier #{new_tier} via loyalty program"
    )
  end

  def send_loyalty_notifications(customer_subscription, points_awarded)
    return unless points_awarded > 0

    # Send email notification for significant point awards (>= 100 points)
    if points_awarded >= 100
      SubscriptionMailer.loyalty_points_awarded(
        customer_subscription.id,
        points_awarded
      ).deliver_later(queue: 'mailers')
    end
  end

  def send_milestone_notification(customer_subscription, milestone_type, points_awarded)
    SubscriptionMailer.milestone_achieved(
      customer_subscription.id,
      milestone_type,
      points_awarded
    ).deliver_later(queue: 'mailers')
  end

  def send_tier_upgrade_notification(customer_subscription, tier_info)
    SubscriptionMailer.tier_upgraded(
      customer_subscription.id,
      tier_info[:tier_name],
      tier_info[:benefits]
    ).deliver_later(queue: 'mailers')
  end
end 
 
 
 
 