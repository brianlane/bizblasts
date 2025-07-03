FactoryBot.define do
  factory :tip do
    association :business
    association :booking
    association :tenant_customer
    
    amount { 5.00 }
    status { :pending }
    
    # Default fee values (will be calculated when tip is processed)
    stripe_fee_amount { nil }
    platform_fee_amount { nil }
    business_amount { nil }
    
    trait :completed do
      status { :completed }
      paid_at { Time.current }
      stripe_payment_intent_id { "pi_#{SecureRandom.hex(8)}" }
      stripe_charge_id { "ch_#{SecureRandom.hex(8)}" }
      stripe_customer_id { "cus_#{SecureRandom.hex(8)}" }
      
      # Calculate fees for completed tips
      after(:build) do |tip|
        if tip.amount.present? && tip.business.present?
          amount_cents = (tip.amount * 100).to_i
          
          # Calculate Stripe fee (2.9% + $0.30)
          stripe_percentage_fee = (amount_cents * 0.029).round
          tip.stripe_fee_amount = (stripe_percentage_fee + 30) / 100.0
          
          # Calculate platform fee based on business tier
          platform_rate = case tip.business.tier
                         when 'premium' then 0.03  # 3%
                         else 0.05                 # 5%
                         end
          tip.platform_fee_amount = (amount_cents * platform_rate).round / 100.0
          
          # Calculate business amount (tip amount - all fees)
          # Business receives net amount after deducting both Stripe and platform fees
          tip.business_amount = tip.amount - tip.stripe_fee_amount - tip.platform_fee_amount
        end
      end
    end
    
    trait :failed do
      status { :failed }
      failure_reason { "Card declined" }
    end
    
    trait :large_amount do
      amount { 25.00 }
    end
    
    trait :premium_business do
      association :business, tier: 'premium'
    end
    
    trait :free_business do
      association :business, tier: 'free'
    end
  end
end 