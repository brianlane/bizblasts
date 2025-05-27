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
    industry { %w[hair_salon beauty_spa massage_therapy fitness_studio tutoring_service cleaning_service handyman_service pet_grooming photography consulting other].sample }
    phone { Faker::PhoneNumber.phone_number }
    sequence(:email) { |n| "business#{n}@example.com" }
    sequence(:subdomain) { |n| "business#{n}" }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    state { Faker::Address.state_abbr }
    zip { Faker::Address.zip_code }
    description { Faker::Company.catch_phrase }
    website { Faker::Internet.url }
    
    # Set tier, ensuring free tier gets subdomain host_type
    tier do 
      if host_type == 'custom_domain'
        [:standard, :premium].sample # Custom domain cannot be free
      else
        # Allow any tier for subdomain, can be overridden by traits
        Business.tiers.keys.sample 
      end
    end

    time_zone { 'UTC' }
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
      transient do
        services_count { 3 }
      end
      
      after(:create) do |business, evaluator|
        create_list(:service, evaluator.services_count, business: business)
      end
    end
    
    trait :with_staff do
      transient do
        staff_count { 2 }
      end
      
      after(:create) do |business, evaluator|
        create_list(:staff_member, evaluator.staff_count, business: business)
      end
    end
    
    trait :with_all do
      with_services
      with_staff
      with_bookings
    end

    trait :with_default_tax_rate do
      after(:create) do |business, evaluator|
        create(:tax_rate, business: business, name: 'Default Tax', rate: 0.098)
      end
    end

    trait :inactive do
      active { false }
    end

    factory :complete_business do
      transient do
        services_count { 3 }
        staff_count { 2 }
        customers_count { 5 }
      end
      
      after(:create) do |business, evaluator|
        # Create services
        services = create_list(:service, evaluator.services_count, business: business)
        
        # Create staff
        staff = create_list(:staff_member, evaluator.staff_count, business: business)
        
        # Associate staff with services
        staff.each do |staff_member|
          services.each do |service|
            create(:services_staff_member, service: service, staff_member: staff_member)
          end
        end
        
        # Create customers
        create_list(:tenant_customer, evaluator.customers_count, business: business)
      end
    end
  end
end