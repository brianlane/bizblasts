# frozen_string_literal: true

FactoryBot.define do
  factory :business do
    to_create { |instance| instance.save(validate: false) }
    # Incorporate parallel worker number for uniqueness
    sequence(:name) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      "Business #{worker_num.present? ? worker_num + '-' : ''}#{n}"
    end
    
    # Default to subdomain host type
    host_type { 'subdomain' }
    
    # Sequence hostname based on host_type
    # Add a short random suffix to guarantee uniqueness even if sequences rewind
    sequence(:hostname) do |n|
      worker_num = ENV['TEST_ENV_NUMBER']
      random_suffix = SecureRandom.alphanumeric(6).downcase
      prefix = "factory-host-#{worker_num.present? ? worker_num + '-' : ''}#{n}-#{random_suffix}"
      # Ensure hostname format matches host_type (simplistic check)
      # Override this in traits or specific create calls if needed
      if host_type == 'custom_domain'
        "#{prefix}.com"
      else
        prefix # Assumed subdomain
      end
    end

    # Default industry to a known valid enum key
    industry { :other }
    phone { Faker::PhoneNumber.phone_number }
    sequence(:email) { |n| "business#{n}@example.com" }
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
        # Always free tier for subdomain
        'free'
      end
    end

    time_zone { 'UTC' }
    active { true }
    stock_management_enabled { true }
    tip_mailer_if_no_tip_received { true }
    
    # Subdomain used for subdomain host type. Default to mirror hostname to
    # satisfy tests that expect `business.hostname` to represent the subdomain.
    subdomain { nil }

    # Ensure for subdomain host type the hostname mirrors the subdomain
    # but do NOT override an explicitly provided hostname in the spec.
    after(:build) do |biz|
      if biz.host_type == 'subdomain'
        # Ensure hostname is present and unique (already set by sequence above)
        biz.hostname = biz.hostname.to_s.downcase.strip.presence || "factory-host-#{SecureRandom.alphanumeric(6).downcase}"
        # Keep subdomain in sync with hostname unless explicitly set
        biz.subdomain ||= biz.hostname
      end
    end
    
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
    
    trait :testbiz do
      sequence(:hostname) { |n| "testbiz-#{n}" }
      sequence(:subdomain) { |n| "testbiz-#{n}" }
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

    trait :with_stripe_account do
      sequence(:stripe_account_id) { |n| "acct_test#{n}" }
    end

    trait :with_custom_domain do
      host_type { 'custom_domain' }
      tier { 'premium' }
      status { 'cname_active' }
      domain_health_verified { true }
      render_domain_added { true }
      sequence(:hostname) { |n| "custom-domain-#{n}.com" }
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