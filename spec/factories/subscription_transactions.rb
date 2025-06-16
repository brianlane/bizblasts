# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_transaction do
    # Required associations
    association :customer_subscription
    
    # Set business and tenant_customer from the customer_subscription
    business { customer_subscription&.business || association(:business) }
    tenant_customer { customer_subscription&.tenant_customer || association(:tenant_customer, business: business) }
    
    # Transaction details
    amount { 45.00 }
    status { 'pending' }
    transaction_type { 'billing' }
    
    # Timestamps
    processed_date { 1.hour.ago.to_date }
    created_at { 1.hour.ago }
    
    # Optional fields
    failure_reason { nil }
    notes { nil }
    
    # Traits for different statuses
    trait :completed do
      status { 'completed' }
      processed_date { 1.hour.ago.to_date }
    end
    
    trait :failed do
      status { 'failed' }
      failure_reason { 'insufficient_funds' }
      processed_date { 1.hour.ago.to_date }
    end
    
    trait :pending do
      status { 'pending' }
      processed_date { Date.current }
    end
    
    trait :cancelled do
      status { 'cancelled' }
      processed_date { 1.hour.ago.to_date }
      notes { 'Transaction cancelled' }
    end
    
    # Traits for different transaction types
    trait :billing do
      transaction_type { 'billing' }
    end
    
    trait :refund do
      transaction_type { 'refund' }
      amount { -45.00 }
    end
    
    trait :failed_payment do
      transaction_type { 'failed_payment' }
      status { 'failed' }
      failure_reason { 'payment_failed' }
      notes { 'Payment processing failed' }
    end
    
    # Traits for different amounts
    trait :high_value do
      amount { 500.00 }
    end
    
    trait :low_value do
      amount { 10.00 }
    end
    
    # Traits for timing
    trait :recent do
      created_at { 1.day.ago }
      processed_date { 1.day.ago.to_date }
    end
    
    trait :old do
      created_at { 6.months.ago }
      processed_date { 6.months.ago.to_date }
    end
    
    # Trait for testing with notes
    trait :with_notes do
      notes { 'Subscription billing processed successfully' }
    end
    
    # Trait for failed payment with specific reason
    trait :card_declined do
      status { 'failed' }
      failure_reason { 'card_declined' }
      notes { 'Customer card was declined' }
    end
    
    trait :insufficient_funds do
      status { 'failed' }
      failure_reason { 'insufficient_funds' }
      notes { 'Insufficient funds in customer account' }
    end
  end
end 