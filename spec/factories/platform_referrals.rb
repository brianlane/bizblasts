FactoryBot.define do
  factory :platform_referral do
    association :referrer_business, factory: :business
    association :referred_business, factory: :business
    referral_code { "BIZ-#{Faker::Alphanumeric.alpha(number: 2).upcase}-#{Faker::Alphanumeric.alphanumeric(number: 6).upcase}" }
    status { 'pending' }
    
    trait :qualified do
      status { 'qualified' }
      qualification_met_at { 1.day.ago }
    end
    
    trait :rewarded do
      status { 'rewarded' }
      qualification_met_at { 2.days.ago }
      reward_issued_at { 1.day.ago }
    end
  end
end 