# frozen_string_literal: true

FactoryBot.define do
  factory :customer_subscription do
    # Required associations
    association :business
    
    # Create tenant_customer that belongs to the same business
    tenant_customer { association(:tenant_customer, business: business) }
    
    # Subscription type - default to service subscription
    subscription_type { 'service_subscription' }
    
    # Service or Product association based on type
    transient do
      create_service { true }
      create_product { false }
    end
    
    # Conditionally create service or product
    service { create_service ? association(:service, business: business) : nil }
    product { create_product ? association(:product, business: business) : nil }
    
    # Billing details
    frequency { 'monthly' }
    quantity { 1 }
    subscription_price { 45.00 }
    billing_day_of_month { 0 } # 0 means no preference, use natural date progression
    
    # Status and dates
    status { :active }
    next_billing_date { 1.month.from_now.to_date }
    created_at { 1.week.ago }
    
    # Stripe integration
    sequence(:stripe_subscription_id) { |n| "sub_test_#{n}" }
    
    # Customer preferences (using actual model fields)
    # Note: customer_preferences JSON field doesn't exist in the model
    
    # Customer rebooking preference
    customer_rebooking_preference { 'same_day_next_month' }
    customer_out_of_stock_preference { 'skip_month' }
    
    # Traits for different subscription types
    trait :service_subscription do
      subscription_type { 'service_subscription' }
      transient do
        create_service { true }
        create_product { false }
      end
    end
    
    trait :product_subscription do
      subscription_type { 'product_subscription' }
      transient do
        create_service { false }
        create_product { true }
      end
    end
    
    # Traits for different billing cycles
    trait :weekly do
      frequency { 'weekly' }
      next_billing_date { 1.week.from_now.to_date }
    end
    
    trait :monthly do
      frequency { 'monthly' }
      next_billing_date { 1.month.from_now.to_date }
    end
    
    trait :quarterly do
      frequency { 'quarterly' }
      next_billing_date { 3.months.from_now.to_date }
    end
    
    trait :yearly do
      frequency { 'annually' }
      next_billing_date { 1.year.from_now.to_date }
    end
    
    # Traits for different statuses
    trait :active do
      status { :active }
    end
    

    
    trait :cancelled do
      status { :cancelled }
      cancelled_at { 1.day.ago }
      cancellation_reason { 'customer_request' }
    end
    
    trait :expired do
      status { :expired }
    end
    
    trait :failed do
      status { :failed }
    end
    
    # Traits for different pricing scenarios
    trait :discounted do
      subscription_price { 80.00 }
    end
    
    trait :no_discount do
      subscription_price { 50.00 }
    end
    
    trait :high_value do
      subscription_price { 450.00 }
    end
    
    # Traits for customer preferences
    trait :with_staff_preference do
      # Use actual model fields instead of non-existent customer_preferences
      customer_rebooking_preference { 'same_day_next_month' }
      customer_out_of_stock_preference { 'skip_month' }
    end
    
    trait :loyalty_points_preference do
      customer_rebooking_preference { 'loyalty_points' }
      customer_out_of_stock_preference { 'loyalty_points' }
    end
    
    trait :soonest_available_preference do
      customer_rebooking_preference { 'soonest_available' }
    end
    
    # Traits for testing edge cases
    trait :due_today do
      next_billing_date { Date.current }
    end
    
    trait :overdue do
      next_billing_date { 1.week.ago.to_date }
      status { :active }
    end
    
    trait :new_subscription do
      created_at { 1.day.ago }
      next_billing_date { 1.month.from_now.to_date }
    end
    
    trait :long_running do
      created_at { 2.years.ago }
      next_billing_date { 1.month.from_now.to_date }
    end
    
    # Traits for different quantities
    trait :multiple_quantity do
      quantity { 3 }
      subscription_price { 90.00 }
    end
    
    # Trait for testing with related records
    trait :with_transactions do
      after(:create) do |subscription|
        create_list(:subscription_transaction, 3, customer_subscription: subscription)
      end
    end
    
    trait :with_recent_transaction do
      after(:create) do |subscription|
        create(:subscription_transaction, 
               customer_subscription: subscription,
               created_at: 1.day.ago,
               status: 'completed')
      end
    end
    
    # Trait for testing business logic
    trait :ready_for_billing do
      status { :active }
      next_billing_date { Date.current }
    end
    
    trait :with_loyalty_program do
      after(:create) do |subscription|
        subscription.business.update!(loyalty_program_enabled: true)
      end
    end
    
    # Factory for complete subscription with all associations
    factory :complete_customer_subscription do
      transient do
        with_staff { true }
        with_loyalty { false }
      end
      
      after(:create) do |subscription, evaluator|
        if evaluator.with_staff && subscription.service_subscription?
          staff_member = create(:staff_member, business: subscription.business)
          subscription.update!(
            customer_preferences: subscription.customer_preferences.merge(
              'preferred_staff_member_id' => staff_member.id
            )
          )
        end
        
        if evaluator.with_loyalty
          subscription.business.update!(loyalty_program_enabled: true)
        end
        
        # Create some transaction history
        create_list(:subscription_transaction, 2, 
                   customer_subscription: subscription,
                   status: 'completed')
      end
    end
  end
end 