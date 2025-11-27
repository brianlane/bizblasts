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

    trait :with_optional_items do
      has_optional_items { true }
      after(:build) do |estimate|
        estimate.estimate_items << build(:estimate_item, :optional, estimate: estimate)
      end
    end

    trait :sent do
      status { :sent }
      sent_at { Time.current }
    end

    trait :viewed do
      status { :viewed }
      sent_at { Time.current - 1.day }
      viewed_at { Time.current }
    end

    trait :approved do
      status { :approved }
      sent_at { Time.current - 2.days }
      viewed_at { Time.current - 1.day }
      approved_at { Time.current }
      deposit_paid_at { Time.current }
    end

    trait :declined do
      status { :declined }
      sent_at { Time.current - 2.days }
      viewed_at { Time.current - 1.day }
      declined_at { Time.current }
    end

    trait :pending_payment do
      status { :pending_payment }
      sent_at { Time.current - 2.days }
      viewed_at { Time.current - 1.day }
      signature_data { "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==" }
      signature_name { "John Doe" }
      signed_at { Time.current }
    end

    trait :with_signature do
      signature_data { "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==" }
      signature_name { "John Doe" }
      signed_at { Time.current }
    end
  end
end
