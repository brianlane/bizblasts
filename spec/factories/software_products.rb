FactoryBot.define do
  factory :software_product do
    sequence(:name) { |n| "Software #{n}" }
    description { "A software product for service businesses" }
    version { "1.0.0" }
    category { "crm" }
    active { true }
    status { "published" }
    license_type { "subscription" }
    features { ["Customer Management", "Invoicing", "Scheduling"] }
    pricing { { monthly: 29.99, yearly: 299.99 } }
    is_saas { true }
    setup_instructions { "Follow the installation guide" }
    documentation_url { "https://example.com/docs" }
    support_url { "https://example.com/support" }
  end
end 