FactoryBot.define do
  factory :platform_loyalty_transaction do
    association :business
    transaction_type { 'earned' }
    points_amount { 100 }
    description { 'Business referral reward for referring Test Business' }
    
    trait :earned do
      transaction_type { 'earned' }
      points_amount { 100 }
    end
    
    trait :redeemed do
      transaction_type { 'redeemed' }
      points_amount { -100 }
      description { 'Redeemed 100 points for $10 subscription discount' }
    end
    
    trait :adjusted do
      transaction_type { 'adjusted' }
      points_amount { 50 }
      description { 'Admin adjustment' }
    end
  end
end 