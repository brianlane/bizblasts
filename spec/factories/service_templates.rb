FactoryBot.define do
  factory :service_template do
    sequence(:name) { |n| "Template #{n}" }
    description { "A website template for service businesses" }
    industry { ServiceTemplate.industries.keys.sample }
    active { true }
    published_at { Time.current }
    template_type { ServiceTemplate.template_types.keys.sample }
    structure { 
      {
        pages: [
          { title: "Home", slug: "home", page_type: "home", content: "Welcome home!" },
          { title: "About", slug: "about", page_type: "about", content: "About us..." },
          { title: "Contact", slug: "contact", page_type: "contact", content: "Contact us!" }
        ],
        theme: "default",
        settings: { show_header: true }
      }
    }
  end
end 