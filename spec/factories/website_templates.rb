FactoryBot.define do
  factory :website_template do
    name { Faker::Lorem.words(number: 2).join(' ').titleize + ' Template' }
    industry { 'universal' }
    template_type { 'universal_template' }
    description { Faker::Lorem.paragraph }
    structure { WebsiteTemplate.default_page_structure }
    default_theme do
      {
        color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME,
        typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
        layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
      }
    end
    preview_image_url { '/assets/template-default.jpg' }
    requires_premium { false }
    active { true }

    trait :industry_specific do
      template_type { 'industry_specific' }
      industry { 'landscaping' }
      name { 'Landscaping Professional Template' }
    end

    trait :premium do
      requires_premium { true }
      name { 'Premium Professional Template' }
    end

    trait :inactive do
      active { false }
    end

    trait :with_custom_structure do
      structure do
        {
          pages: [
            {
              title: 'Custom Home',
              slug: 'home',
              page_type: 'home',
              sections: [
                { type: 'hero_banner', position: 0 },
                { type: 'service_list', position: 1 },
                { type: 'product_list', position: 2 }
              ]
            }
          ]
        }
      end
    end
  end
end 