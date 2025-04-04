# frozen_string_literal: true

FactoryBot.define do
  factory :business do
    # Incorporate parallel worker number for uniqueness
    sequence(:name) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      "Business #{worker_num.present? ? worker_num + '-' : ''}#{n}"
    end
    sequence(:subdomain) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      "test-business-#{worker_num.present? ? worker_num + '-' : ''}#{n}"
    end
    
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