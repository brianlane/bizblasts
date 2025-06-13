FactoryBot.define do
  factory :platform_discount_code do
    association :business
    code { "BIZBLASTS-#{Faker::Alphanumeric.alphanumeric(number: 8).upcase}" }
    points_redeemed { 100 }
    discount_amount { 10.0 }
    status { 'active' }
    stripe_coupon_id { "coupon_test_#{SecureRandom.hex(8)}" }
    
    trait :referral_reward do
      code { "BIZBLASTS-REFERRAL-#{Faker::Alphanumeric.alphanumeric(number: 8).upcase}" }
      points_redeemed { 0 } # Referral rewards don't use points
      discount_amount { 50.0 } # 50% off
    end
    
    trait :loyalty_redemption do
      points_redeemed { 200 }
      discount_amount { 20.0 } # $20 off
    end
    
    trait :used do
      status { 'used' }
    end
    
    trait :expired do
      status { 'expired' }
      expires_at { 1.day.ago }
    end
  end
end 