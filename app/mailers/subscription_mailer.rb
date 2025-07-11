# frozen_string_literal: true

class SubscriptionMailer < ApplicationMailer
  def signup_confirmation(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Set unsubscribe token for the customer
    set_unsubscribe_token(@customer)
    
    # Always send transactional emails regardless of marketing preferences
    mail(
      to: @customer.email,
      subject: "Subscription Confirmed - #{@item.name}",
      from: @business.email,
      reply_to: @business.email,
      headers: { 'X-Subscription-ID' => @customer_subscription.id.to_s }
    )
  end

  def payment_succeeded(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Set unsubscribe token for the customer
    set_unsubscribe_token(@customer)
    
    mail(
      to: @customer.email,
      subject: "Subscription Payment Processed - #{@item.name}",
      from: @business.email
    )
  end

  def payment_failed(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Set unsubscribe token for the customer
    set_unsubscribe_token(@customer)
    
    mail(
      to: @customer.email,
      subject: "Subscription Payment Failed - #{@item.name}",
      from: @business.email
    )
  end

  def subscription_cancelled(customer_subscription)
    @customer_subscription = customer_subscription
    @customer = customer_subscription.tenant_customer
    @business = customer_subscription.business
    @item = customer_subscription.product || customer_subscription.service

    # Set unsubscribe token for the customer
    set_unsubscribe_token(@customer)

    mail(
      to: @customer.email,
      subject: "Subscription Cancelled - #{@item.name}",
      template_path: 'subscription_mailer',
      template_name: 'subscription_cancelled'
    )
  end

  def payment_processed(customer_subscription, amount)
    @customer_subscription = customer_subscription
    @customer = customer_subscription.tenant_customer
    @business = customer_subscription.business
    @item = customer_subscription.item
    @amount = amount

    mail(
      to: @customer.email,
      subject: "Payment Processed - #{@item.name}",
      template_path: 'subscription_mailer',
      template_name: 'payment_processed'
    )
  end



  def permanent_failure(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    mail(
      to: @customer.email,
      subject: "Subscription Cancelled Due to Payment Issues - #{@item.name}",
      from: @business.email
    )
  end

  def subscription_updated(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    mail(
      to: @customer.email,
      subject: "Subscription Updated - #{@item.name}",
      from: @business.email
    )
  end

  def subscription_confirmed(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    mail(
      to: @customer.email,
      subject: "Subscription Confirmed - #{@item.name}",
      from: @business.email,
      reply_to: @business.email,
      headers: { 'X-Subscription-ID' => @customer_subscription.id.to_s }
    )
  end

  # Loyalty-related emails
  def loyalty_points_awarded(customer_subscription_id, points_awarded)
    @customer_subscription = CustomerSubscription.find(customer_subscription_id)
    @business = @customer_subscription.business
    @customer = @customer_subscription.tenant_customer
    @points_awarded = points_awarded
    @current_points = @customer.current_loyalty_points
    
    mail(
      to: @customer.email,
      subject: "#{@points_awarded} loyalty points earned from your #{@business.name} subscription!",
      template_name: 'loyalty_points_awarded'
    )
  end

  def milestone_achieved(customer_subscription_id, milestone_type, points_awarded)
    @customer_subscription = CustomerSubscription.find(customer_subscription_id)
    @business = @customer_subscription.business
    @customer = @customer_subscription.tenant_customer
    @milestone_type = milestone_type
    @points_awarded = points_awarded
    @milestone_name = milestone_display_name(milestone_type)
    @current_points = @customer.current_loyalty_points
    
    mail(
      to: @customer.email,
      subject: "🎉 Congratulations! You've reached a #{@milestone_name} milestone with #{@business.name}",
      template_name: 'milestone_achieved'
    )
  end

  def tier_upgraded(customer_subscription_id, tier_name, benefits)
    @customer_subscription = CustomerSubscription.find(customer_subscription_id)
    @business = @customer_subscription.business
    @customer = @customer_subscription.tenant_customer
    @tier_name = tier_name
    @benefits = benefits
    @current_points = @customer.current_loyalty_points
    
    mail(
      to: @customer.email,
      subject: "🌟 You've been upgraded to #{@tier_name} tier with #{@business.name}!",
      template_name: 'tier_upgraded'
    )
  end

  def loyalty_redemption_confirmation(customer_subscription_id, benefit_type, benefit_value, points_redeemed)
    @customer_subscription = CustomerSubscription.find(customer_subscription_id)
    @business = @customer_subscription.business
    @customer = @customer_subscription.tenant_customer
    @benefit_type = benefit_type
    @benefit_value = benefit_value
    @points_redeemed = points_redeemed
    @remaining_points = @customer.current_loyalty_points
    @benefit_description = redemption_benefit_description(benefit_type, benefit_value)
    
    mail(
      to: @customer.email,
      subject: "Loyalty points redeemed successfully - #{@business.name}",
      template_name: 'loyalty_redemption_confirmation'
    )
  end

  private

  def milestone_display_name(milestone_type)
    case milestone_type
    when 'first_month' then '1 Month'
    when 'three_months' then '3 Month'
    when 'six_months' then '6 Month'
    when 'one_year' then '1 Year'
    when 'two_years' then '2 Year'
    else milestone_type.humanize
    end
  end

  def redemption_benefit_description(benefit_type, benefit_value)
    case benefit_type
    when 'subscription_discount'
      "#{benefit_value}% discount on your next subscription payment"
    when 'free_month'
      "One month free (payment skipped, subscription continues)"
    when 'upgrade_variant'
      "Premium variant upgrade for your next delivery"
    else
      "Special loyalty benefit"
    end
  end
end 
 
 
 
 