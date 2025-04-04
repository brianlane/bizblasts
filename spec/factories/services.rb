# frozen_string_literal: true

FactoryBot.define do
  factory :service do
    # Simple sequence to avoid validation complexity
    sequence(:name) { |n| "Service #{n}" }
    description { "Test service" }
    duration { 60 }
    price { 50 }
    active { true }
    
    # Skip callbacks for test performance
    to_create { |instance| 
      instance.save(validate: false) 
    }
    
    # Use build strategy for associations to minimize DB operations
    association :business, strategy: :build
    
    trait :with_staff_members do
      after(:create) do |service, evaluator|
        # Only create what's absolutely necessary
        service.staff_members << create(:staff_member, business: service.business)
      end
    end
  end
end
