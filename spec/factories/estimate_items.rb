FactoryBot.define do
  factory :estimate_item do
    association :estimate
    association :service
    item_type { :service }
    description { "Test item" }
    qty { 1 }
    cost_rate { "10.00" }
    tax_rate { nil }
    total { cost_rate.to_d * (qty || 1) }
    optional { false }
    customer_selected { true }
    customer_declined { false }
    position { 0 }

    trait :optional do
      optional { true }
      customer_selected { false }
    end

    trait :optional_selected do
      optional { true }
      customer_selected { true }
      customer_declined { false }
    end

    trait :optional_declined do
      optional { true }
      customer_selected { false }
      customer_declined { true }
    end

    trait :product_item do
      item_type { :product }
      service { nil }
      association :product
    end

    trait :labor_item do
      item_type { :labor }
      service { nil }
      description { "Labor work" }
      hours { 2.5 }
      hourly_rate { 50.00 }
      cost_rate { 50.00 }
      qty { 3 } # Rounded up hours
      total { 125.00 } # hours * hourly_rate
    end

    trait :part_item do
      item_type { :part }
      service { nil }
      description { "Replacement part" }
    end
  end
end
