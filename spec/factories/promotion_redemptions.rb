FactoryBot.define do
  factory :promotion_redemption do
    association :promotion
    association :tenant_customer
    redeemed_at { Time.current }
  end
end 