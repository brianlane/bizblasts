FactoryBot.define do
  factory :promotion_redemption do
    promotion
    tenant_customer { association :tenant_customer, business: promotion.business }
    redeemed_at { Time.current }
  end
end 