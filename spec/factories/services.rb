# frozen_string_literal: true

FactoryBot.define do
  factory :service do
    name { Faker::Commerce.product_name }
    description { Faker::Lorem.paragraph }
    duration { [30, 60, 90, 120].sample }
    price { Faker::Commerce.price(range: 20..200.0) }
    active { true }
    featured { false }
    association :business
    
    availability_settings { {} }
    
    trait :inactive do
      active { false }
    end
    
    trait :featured do
      featured { true }
    end
    
    trait :with_availability_settings do
      availability_settings do
        {
          'advance_booking_max_days' => 30,
          'advance_booking_min_hours' => 2,
          'double_booking_allowed' => false,
          'customer_cancelation_hours' => 24,
          'availability_increment' => 30,
          'priority_staff' => []
        }
      end
    end
    
    factory :service_with_staff_members do
      transient do
        staff_members_count { 2 }
      end
      
      after(:create) do |service, evaluator|
        create_list(:staff_member, evaluator.staff_members_count, business: service.business).each do |staff|
          create(:services_staff_member, service: service, staff_member: staff)
        end
      end
    end
  end
end
