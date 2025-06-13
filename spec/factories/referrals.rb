FactoryBot.define do
  factory :referral do
    business
    association :referrer, factory: :user
    referral_code { "REF-#{SecureRandom.alphanumeric(8).upcase}" }
    status { 'pending' }
    
    trait :pending do
      status { 'pending' }
    end
    
    trait :qualified do
      status { 'qualified'  }
      qualification_met_at { 1.day.ago }
      association :referred_tenant_customer, factory: :tenant_customer
    end
    
    trait :rewarded do
      status { 'rewarded' }
      qualification_met_at { 2.days.ago }
      reward_issued_at { 1.day.ago }
      association :referred_tenant_customer, factory: :tenant_customer
    end
    
    trait :with_referred_customer do
      association :referred_tenant_customer, factory: :tenant_customer
    end
    
    trait :with_booking do
      association :qualifying_booking, factory: :booking
      association :referred_tenant_customer, factory: :tenant_customer
    end
    
    trait :with_order do
      association :qualifying_order, factory: :order  
      association :referred_tenant_customer, factory: :tenant_customer
    end
  end
end 