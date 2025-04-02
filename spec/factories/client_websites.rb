FactoryBot.define do
  factory :client_website do
    sequence(:name) { |n| "Website #{n}" }
    sequence(:subdomain) { |n| "website#{n}" }
    domain { nil }
    active { true }
    status { "draft" }
    custom_domain_enabled { false }
    ssl_enabled { false }
    content { { headline: "Welcome", description: "Our Services" } }
    settings { { show_contact: true, enable_booking: true } }
    theme { { primary_color: "#336699", font: "Arial" } }
    seo_settings { { meta_title: "Business Name", meta_description: "Our services" } }
    association :company
    association :service_template
  end
end 