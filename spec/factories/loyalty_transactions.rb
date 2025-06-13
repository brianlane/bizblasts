FactoryBot.define do
  factory :loyalty_transaction do
    business
    tenant_customer
    transaction_type { 'earned' }
    points_amount { 100 }
    description { 'Test loyalty transaction' }
    
    trait :earned do
      transaction_type { 'earned' }
      points_amount { 100 }
      description { 'Points earned from booking' }
    end
    
    trait :redeemed do
      transaction_type { 'redeemed' }
      points_amount { -50 }
      description { 'Points redeemed for discount' }
    end
    
    trait :expired do
      transaction_type { 'expired' }
      points_amount { -25 }
      description { 'Points expired' }
      expires_at { 1.day.ago }
    end
    
    trait :adjusted do
      transaction_type { 'adjusted' }
      points_amount { 10 }
      description { 'Points adjusted by admin' }
    end
    
    trait :with_booking do
      association :related_booking, factory: :booking
    end
    
    trait :with_order do
      association :related_order, factory: :order
    end
    
    trait :with_referral do
      association :related_referral, factory: :referral
    end
  end
end 