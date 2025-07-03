FactoryBot.define do
  factory :estimate do
    association :business
    association :tenant_customer
    proposed_start_time { Time.current + 1.day }
    required_deposit { 0.0 }
    subtotal { 0.0 }
    taxes { 0.0 }
    total { 0.0 }
    status { :draft }

    after(:build) do |estimate|
      estimate.estimate_items << build(:estimate_item, estimate: estimate)
    end
  end
end
