FactoryBot.define do
  factory :shipping_method do
    sequence(:name) { |n| "Shipping #{n}" }
    cost { rand(5.0..25.0).round(2) }
    active { true }
    association :business # Assuming you have a business factory

    trait :inactive do
      active { false }
    end
  end
end 