# frozen_string_literal: true

FactoryBot.define do
  factory :business do
    # Use a simple sequence to avoid complex validations
    sequence(:name) { |n| "Business #{n}" }
    sequence(:subdomain) { |n| "test-business-#{n}" }
    
    # Set default values rather than generating them
    time_zone { "UTC" }
    active { true }
    
    # Skip callbacks for test performance
    to_create { |instance| 
      instance.save(validate: false) 
    }
    
    trait :with_bookings do
      after(:create) do |business, evaluator|
        # Create minimal bookings
        create_list(:booking, 3, business: business)
      end
    end
    
    trait :with_services do
      after(:create) do |business, evaluator|
        # Create minimal services
        create_list(:service, 3, business: business)
      end
    end
    
    trait :with_staff do
      after(:create) do |business, evaluator|
        # Create minimal staff
        create_list(:staff_member, 2, business: business)
      end
    end
    
    trait :with_all do
      with_services
      with_staff
      with_bookings
    end
  end
end 