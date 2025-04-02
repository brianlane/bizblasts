FactoryBot.define do
  factory :software_subscription do
    status { "active" }
    started_at { 1.day.ago }
    ends_at { 1.year.from_now }
    sequence(:license_key) { |n| "LICENSE-#{n}-#{SecureRandom.hex(8)}" }
    subscription_type { "monthly" }
    subscription_details { { plan: "standard" } }
    auto_renew { true }
    payment_status { "paid" }
    usage_metrics { { logins: 5, actions: 25 } }
    association :company
    association :software_product
  end
end 