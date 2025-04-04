# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # Simple sequence to avoid validation complexity
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :admin }
    active { true }
    
    # Use build strategy for associations to minimize DB operations
    association :business, strategy: :build
    
    # Skip callbacks for test performance
    to_create { |instance| 
      instance.save(validate: false) 
    }
    
    trait :with_staff_member do
      association :staff_member, strategy: :build
    end
    
    trait :admin do
      role { :admin }
    end
    
    trait :manager do
      role { :manager }
    end
    
    trait :staff do
      role { :staff }
    end
    
    trait :client do
      role { :client }
    end
  end
end 