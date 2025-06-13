FactoryBot.define do
  factory :loyalty_program do
    business
    name { "#{business&.name || 'Test Business'} Loyalty Program" }
    points_name { 'points' }
    points_per_dollar { 1.0 }
    points_for_booking { 10 }
    points_for_referral { 100 }
    active { true }
    
    trait :active do
      active { true }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :generous do
      points_per_dollar { 2.0 }
      points_for_booking { 25 }
      points_for_referral { 200 }
    end
    
    trait :minimal do
      points_per_dollar { 0.5 }
      points_for_booking { 5 }
      points_for_referral { 50 }
    end
  end
end 