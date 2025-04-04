FactoryBot.define do
  factory :promotion do
    association :business
    name { "Summer Sale" }
    sequence(:code) { |n| "SUMMER#{n}" }
    start_date { 1.week.ago }
    end_date { 1.month.from_now }
    discount_type { :percentage } 
    discount_value { 10 } # e.g., 10%
    usage_limit { nil } # Unlimited unless specified
    current_usage { 0 }
    active { true }
    
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