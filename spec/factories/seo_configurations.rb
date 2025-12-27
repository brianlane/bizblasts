# frozen_string_literal: true

FactoryBot.define do
  factory :seo_configuration do
    association :business
    
    meta_title_template { '{{business_name}} | {{page_title}} in {{city}}, {{state}}' }
    meta_description_template { '{{business_name}} offers professional {{industry}} services in {{city}}, {{state}}. {{description}}' }
    
    target_keywords { ['local business', 'services near me', 'best in town'] }
    auto_keywords { [] }
    competitor_domains { [] }
    
    seo_score { rand(40..85) }
    seo_score_breakdown do
      {
        title_score: rand(60..100),
        description_score: rand(50..100),
        content_score: rand(40..90),
        local_seo_score: rand(50..100),
        technical_score: rand(60..100),
        image_score: rand(30..80),
        linking_score: rand(40..80),
        mobile_score: rand(70..100)
      }
    end
    
    seo_suggestions do
      [
        { priority: 'high', category: 'title', suggestion: 'Add city name to title tag', impact: 15 },
        { priority: 'medium', category: 'content', suggestion: 'Expand service descriptions to 100+ words', impact: 10 },
        { priority: 'low', category: 'images', suggestion: 'Add alt text to all images', impact: 5 }
      ]
    end
    
    keyword_rankings do
      {
        'hair salon portland' => { position: 15, trend: 'improving', last_checked: Time.current.iso8601 },
        'best salon near me' => { position: 25, trend: 'stable', last_checked: Time.current.iso8601 }
      }
    end
    
    local_business_schema { {} }
    
    sitemap_enabled { true }
    sitemap_priority { '0.8' }
    sitemap_changefreq { 'weekly' }
    allow_indexing { true }

    trait :excellent_seo do
      seo_score { rand(85..100) }
      seo_score_breakdown do
        {
          title_score: rand(90..100),
          description_score: rand(90..100),
          content_score: rand(85..100),
          local_seo_score: rand(90..100),
          technical_score: rand(90..100),
          image_score: rand(80..100),
          linking_score: rand(80..100),
          mobile_score: rand(95..100)
        }
      end
      seo_suggestions { [] }
    end

    trait :poor_seo do
      seo_score { rand(10..30) }
      seo_score_breakdown do
        {
          title_score: rand(10..40),
          description_score: rand(10..30),
          content_score: rand(10..30),
          local_seo_score: rand(20..40),
          technical_score: rand(30..50),
          image_score: rand(10..30),
          linking_score: rand(10..30),
          mobile_score: rand(40..60)
        }
      end
      seo_suggestions do
        [
          { priority: 'high', category: 'title', suggestion: 'Add unique title tag', impact: 20 },
          { priority: 'high', category: 'description', suggestion: 'Add meta description', impact: 15 },
          { priority: 'high', category: 'content', suggestion: 'Add more content to pages', impact: 20 },
          { priority: 'high', category: 'local', suggestion: 'Add business address to footer', impact: 15 },
          { priority: 'medium', category: 'images', suggestion: 'Add alt text to images', impact: 10 }
        ]
      end
    end

    trait :with_google_verification do
      google_site_verification { "google-site-verification-#{SecureRandom.hex(16)}" }
      google_analytics_id { "G-#{SecureRandom.alphanumeric(10).upcase}" }
    end

    trait :noindex do
      allow_indexing { false }
      robots_txt_additions { "Disallow: /admin/\nDisallow: /api/" }
    end
  end
end

