FactoryBot.define do
  factory :discount_code do
    business
    association :used_by_customer, factory: :tenant_customer
    code { "DISC#{SecureRandom.hex(4).upcase}" }
    discount_type { 'fixed_amount' }
    discount_value { 10.00 }
    active { true }
    expires_at { 30.days.from_now }
    
    trait :active do
      active { true }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :used do
      active { false }
      used_at { 1.day.ago }
    end
    
    trait :expired do
      active { false }
      expires_at { 1.day.ago }
    end
    
    trait :high_value do
      discount_value { 50.00 }
    end
  end
end 