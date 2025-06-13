FactoryBot.define do
  factory :promotion do
    association :business
    name { "Summer Sale" }
    code { nil } # Default to automatic promotion (no code)
    start_date { 1.week.ago }
    end_date { 1.month.from_now }
    discount_type { :percentage } 
    discount_value { 10 } # e.g., 10%
    usage_limit { nil } # Unlimited unless specified
    current_usage { 0 }
    active { true }
    allow_discount_codes { true } # Can be true for automatic promotions
    
    trait :automatic do
      code { nil }
      allow_discount_codes { true }
    end
    
    trait :code_based do
      sequence(:code) { |n| "PROMO#{n}" }
      allow_discount_codes { false } # Code-based promotions cannot stack
    end
    
    trait :percentage do
      discount_type { :percentage }
      discount_value { 15 }
    end
    
    trait :fixed_amount do
      discount_type { :fixed_amount }
      discount_value { 5.00 }
    end
    
    trait :inactive do
      start_date { 2.months.ago }
      end_date { 1.month.ago }
      active { false }
    end
    
    trait :usage_limited do
      usage_limit { 5 }
    end
    
    trait :single_use_by_limit do
      usage_limit { 1 }
    end
  end
end 