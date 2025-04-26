# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    start_time { 1.day.from_now.change(hour: 10) }
    end_time { 
      if service && service.duration && start_time
        start_time + service.duration.minutes
      else
        start_time ? start_time + 1.hour : 1.day.from_now.change(hour: 11) # Fallback
      end
    }
    status { :pending }
    notes { Faker::Lorem.paragraph }
    association :service
    association :staff_member
    association :tenant_customer
    association :business
    
    trait :confirmed do
      status { :confirmed }
    end
    
    trait :cancelled do
      status { :cancelled }
    end
    
    trait :completed do
      status { :completed }
      start_time { 1.day.ago.change(hour: 10) }
      end_time { 1.day.ago.change(hour: 11) }
    end
    
    trait :no_show do
      status { :no_show }
      start_time { 1.day.ago.change(hour: 10) }
      end_time { 1.day.ago.change(hour: 11) }
    end
    
    trait :with_promotion do
      association :promotion
      original_amount { service&.price || 100 }
      discount_amount { 10 }
      amount { original_amount - discount_amount }
    end
  end
end 