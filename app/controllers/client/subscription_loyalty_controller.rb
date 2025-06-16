# frozen_string_literal: true

class Client::SubscriptionLoyaltyController < ApplicationController
  before_action :set_customer_subscription, only: [:show, :redeem_points]
  before_action :check_loyalty_program_enabled

  def index
    @customer_subscriptions = current_customer.customer_subscriptions.active.includes(:business, :product, :service)
    @loyalty_summary = calculate_overall_loyalty_summary
    @tier_benefits = calculate_overall_tier_benefits
    @available_redemptions = calculate_available_redemptions
  end

  def show
    @loyalty_summary = @customer_subscription.loyalty_summary
    @tier_benefits = @customer_subscription.loyalty_tier_benefits
    @redemption_options = @customer_subscription.loyalty_redemption_options
    @loyalty_history = get_subscription_loyalty_history
  end

  def redeem_points
    points = params[:points].to_i
    benefit_type = params[:benefit_type]
    benefit_value = params[:benefit_value].to_i

    return redirect_with_error('Invalid redemption parameters') if points <= 0 || benefit_type.blank?

    loyalty_service = SubscriptionLoyaltyService.new(@customer_subscription)
    result = loyalty_service.redeem_points_for_subscription_benefit(points, benefit_type, benefit_value)

    if result[:success]
      redirect_to client_subscription_loyalty_path(@customer_subscription), 
                  notice: result[:description]
    else
      redirect_to client_subscription_loyalty_path(@customer_subscription), 
                  alert: result[:error]
    end
  end

  def tier_progress
    @customer_subscriptions = current_customer.customer_subscriptions.active
    @tier_progress_data = calculate_tier_progress_data
    
    respond_to do |format|
      format.html
      format.json { render json: @tier_progress_data }
    end
  end

  def milestones
    @customer_subscriptions = current_customer.customer_subscriptions.includes(:business, :product, :service)
    @milestone_data = calculate_milestone_data
  end

  private

  def set_customer_subscription
    @customer_subscription = current_customer.customer_subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to client_subscription_loyalty_index_path, alert: 'Subscription not found'
  end

  def check_loyalty_program_enabled
    # Check if any of the customer's businesses have loyalty programs enabled
    has_loyalty_enabled = current_customer.customer_subscriptions
                                         .joins(:business)
                                         .where(businesses: { loyalty_program_enabled: true })
                                         .exists?

    unless has_loyalty_enabled
      redirect_to client_subscriptions_path, alert: 'Loyalty program features are not available'
    end
  end

  def calculate_overall_loyalty_summary
    total_points_earned = 0
    total_milestones = 0
    active_subscriptions = 0

    current_customer.customer_subscriptions.active.each do |subscription|
      next unless subscription.business.loyalty_program_enabled?

      summary = subscription.loyalty_summary
      total_points_earned += summary[:subscription_points_earned] || 0
      total_milestones += summary[:subscription_milestones_achieved]&.count || 0
      active_subscriptions += 1
    end

    {
      total_subscription_points_earned: total_points_earned,
      total_milestones_achieved: total_milestones,
      active_loyalty_subscriptions: active_subscriptions,
      current_total_points: current_customer.current_loyalty_points
    }
  end

  def calculate_overall_tier_benefits
    tier_data = {}

    current_customer.customer_subscriptions.active.each do |subscription|
      next unless subscription.business.loyalty_program_enabled?

      business_name = subscription.business.name
      tier_benefits = subscription.loyalty_tier_benefits
      
      tier_data[business_name] = tier_benefits if tier_benefits.present?
    end

    tier_data
  end

  def calculate_available_redemptions
    redemptions = []

    current_customer.customer_subscriptions.active.each do |subscription|
      next unless subscription.business.loyalty_program_enabled?

      options = subscription.loyalty_redemption_options
      options.each do |option|
        redemptions << option.merge(
          subscription_id: subscription.id,
          subscription_name: subscription.item_name,
          business_name: subscription.business.name
        )
      end
    end

    redemptions.sort_by { |r| r[:points_required] }
  end

  def get_subscription_loyalty_history
    loyalty_service = SubscriptionLoyaltyService.new(@customer_subscription)
    loyalty_service.send(:get_loyalty_subscription_history)
  end

  def calculate_tier_progress_data
    progress_data = {}

    current_customer.customer_subscriptions.active.each do |subscription|
      next unless subscription.business.loyalty_program_enabled?

      business_name = subscription.business.name
      tier_benefits = subscription.loyalty_tier_benefits
      
      if tier_benefits[:progress_to_next_tier]
        progress_data[business_name] = {
          current_tier: tier_benefits[:tier_name],
          next_tier: tier_benefits[:next_tier] ? SubscriptionLoyaltyService.new(subscription).send(:tier_name, tier_benefits[:next_tier]) : nil,
          progress: tier_benefits[:progress_to_next_tier]
        }
      end
    end

    progress_data
  end

  def calculate_milestone_data
    milestone_data = []

    @customer_subscriptions.each do |subscription|
      next unless subscription.business.loyalty_program_enabled?

      loyalty_service = SubscriptionLoyaltyService.new(subscription)
      achieved_milestones = loyalty_service.send(:get_achieved_milestones)
      upcoming_rewards = loyalty_service.send(:calculate_upcoming_rewards)

      milestone_data << {
        subscription: subscription,
        achieved_milestones: achieved_milestones,
        upcoming_rewards: upcoming_rewards,
        months_active: ((Time.current - subscription.created_at) / 1.month).to_i
      }
    end

    milestone_data
  end

  def redirect_with_error(message)
    redirect_to client_subscription_loyalty_path(@customer_subscription), alert: message
  end
end 
 
