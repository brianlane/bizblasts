# frozen_string_literal: true

FactoryBot.define do
  factory :business do
    # Incorporate parallel worker number for uniqueness
    sequence(:name) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      "Business #{worker_num.present? ? worker_num + '-' : ''}#{n}"
    end
    
    # Default to subdomain host type
    host_type { 'subdomain' }
    
    # Sequence hostname based on host_type
    sequence(:hostname) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      prefix = "factory-host-#{worker_num.present? ? worker_num + '-' : ''}#{n}"
      # Ensure hostname format matches host_type (simplistic check)
      # Override this in traits or specific create calls if needed
      if host_type == 'custom_domain'
        "#{prefix}.com" 
      else
        prefix # Assumed subdomain
      end
    end 

    # Add required fields with valid defaults
    industry { Business.industries.keys.sample } 
    phone { "123-456-7890" } 
    sequence(:email) { |n| "business#{n}@example.com" } 
    address { "123 Main St" }
    city { "Anytown" }
    state { "CA" }
    zip { "12345" }
    description { "A test business description." }
    
    # Set tier, ensuring free tier gets subdomain host_type
    tier do 
      if host_type == 'custom_domain'
        [:standard, :premium].sample # Custom domain cannot be free
      else
        # Allow any tier for subdomain, can be overridden by traits
        Business.tiers.keys.sample 
      end
    end

    time_zone { "UTC" }
    active { true }
    
    # Traits for specific host types/tiers
    trait :subdomain_host do
      host_type { 'subdomain' }
      sequence(:hostname) { |n| "factory-subdomain-#{n}" } 
    end

    trait :custom_domain_host do
      host_type { 'custom_domain' }
      sequence(:hostname) { |n| "factory-domain-#{n}.com" } 
      tier { [:standard, :premium].sample } # Cannot be free tier
    end
    
    trait :free_tier do
      tier { 'free' }
      host_type { 'subdomain' } # Enforce constraint
      sequence(:hostname) { |n| "factory-free-#{n}" } 
    end

    trait :standard_tier do
      tier { 'standard' }
      # No host_type change needed here, default sequence handles both
    end

    trait :premium_tier do
      tier { 'premium' }
      # No host_type change needed here, default sequence handles both
    end
    
    trait :with_bookings do
      after(:create) do |business, evaluator|
        create_list(:booking, 3, business: business)
      end
    end
    
    trait :with_services do
      after(:create) do |business, evaluator|
        create_list(:service, 3, business: business)
      end
    end
    
    trait :with_staff do
      after(:create) do |business, evaluator|
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