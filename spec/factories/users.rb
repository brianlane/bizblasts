# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # Simple sequence to avoid validation complexity
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { "Test" }
    sequence(:last_name) { |n| "User#{n}" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :client }
    active { true }
    # Confirm users by default for tests
    confirmed_at { Time.current }
    
    # Business association is optional, only add if needed or role requires
    # association :business, strategy: :build 
    
    # Allow normal validation and callbacks for proper confirmation handling
    # Skip callbacks for test performance only when explicitly needed
    # to_create { |instance| 
    #   instance.save(validate: false) 
    # }
    
    trait :unconfirmed do
      confirmed_at { nil }
    end
    
    trait :with_staff_member do
      association :staff_member, strategy: :build
    end
    
    trait :manager do
      role { :manager }
      # Managers require a business
      association :business
    end
    
    trait :staff do
      role { :staff }
      # Staff require a business
      association :business
    end
    
    trait :client do
      role { :client }
    end
  end
end 