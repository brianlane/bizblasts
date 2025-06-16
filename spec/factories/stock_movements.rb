FactoryBot.define do
  factory :stock_movement do
    association :product
    quantity { 10 }
    movement_type { "subscription_fulfillment" }
    reference_id { "ORDER-#{SecureRandom.hex(6)}" }
    reference_type { "Order" }
    notes { "Stock movement for testing" }

    trait :inbound do
      quantity { 15 }
      movement_type { "restock" }
      notes { "Inbound stock movement" }
    end

    trait :outbound do
      quantity { -5 }
      movement_type { "subscription_fulfillment" }
      notes { "Outbound stock movement" }
    end

    trait :adjustment do
      quantity { [-3, -2, -1, 1, 2, 3].sample }
      movement_type { "adjustment" }
      notes { "Stock adjustment" }
    end

    trait :return do
      quantity { 2 }
      movement_type { "return" }
      notes { "Product return" }
    end
  end
end
