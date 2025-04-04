# frozen_string_literal: true

FactoryBot.define do
  factory :staff_member do
    # Simple sequence to avoid validation complexity
    sequence(:name) { |n| "Staff #{n}" }
    sequence(:email) { |n| "staff#{n}@example.com" }
    
    # Static data to avoid computations
    phone { "555-123-4567" }
    bio { "Test staff member" }
    active { true }
    
    # Skip callbacks for test performance
    to_create { |instance| 
      instance.save(validate: false) 
    }
    
    # Use build strategy for associations to minimize DB operations
    association :business, strategy: :build
    
    trait :with_services do
      after(:create) do |staff_member, evaluator|
        # Only create what's absolutely necessary
        staff_member.services << create(:service, business: staff_member.business)
      end
    end
  end
end 