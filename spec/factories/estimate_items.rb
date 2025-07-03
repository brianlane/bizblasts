FactoryBot.define do
  factory :estimate_item do
    association :estimate
    association :service
    description { "Test item" }
    qty { 1 }
    cost_rate { "10.00" }
    tax_rate { nil }
    total { cost_rate.to_d * qty }
  end
end
