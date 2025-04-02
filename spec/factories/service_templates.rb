FactoryBot.define do
  factory :service_template do
    sequence(:name) { |n| "Template #{n}" }
    description { "A website template for service businesses" }
    category { "service" }
    industry { "general" }
    active { true }
    status { "published" }
    features { ["Responsive Design", "SEO Friendly", "Contact Form"] }
    pricing { { monthly: 49.99, yearly: 499.99 } }
    content { { headline: "Welcome", description: "Our Services" } }
    settings { { show_contact: true, enable_booking: true } }
  end
end 