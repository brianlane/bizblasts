FactoryBot.define do
  factory :website_theme do
    association :business
    sequence(:name) { |n| "Theme #{n}" }
    color_scheme { 
      {
        'primary' => '#3b82f6',
        'secondary' => '#6b7280',
        'accent' => '#10b981',
        'dark' => '#111827',
        'light' => '#f9fafb'
      }
    }
    typography {
      {
        'heading_font' => 'Inter',
        'body_font' => 'Inter',
        'font_size_base' => '16px',
        'font_weight_normal' => '400',
        'font_weight_bold' => '600'
      }
    }
    layout_config {
      {
        'header_style' => 'modern',
        'container_width' => 'max-w-7xl',
        'section_spacing' => 'normal',
        'border_radius' => '8px'
      }
    }
    custom_css { "/* Custom theme styles */" }
    active { false }
    
    trait :active do
      active { true }
      
      after(:create) do |theme|
        # Ensure only one active theme per business
        theme.business.website_themes.where.not(id: theme.id).update_all(active: false)
      end
    end
    
    trait :with_preview_image do
      after(:build) do |theme|
        theme.preview_image.attach(
          io: StringIO.new("fake image content"),
          filename: "theme_preview.jpg",
          content_type: "image/jpeg"
        )
      end
    end
    
    trait :landscaping do
      name { "Landscaping Pro" }
      color_scheme {
        {
          'primary' => '#16a34a',
          'secondary' => '#22c55e',
          'accent' => '#84cc16',
          'dark' => '#111827',
          'light' => '#f9fafb'
        }
      }
    end
    
    trait :modern do
      name { "Modern Business" }
      color_scheme {
        {
          'primary' => '#3b82f6',
          'secondary' => '#1e40af',
          'accent' => '#06b6d4',
          'dark' => '#0f172a',
          'light' => '#f8fafc'
        }
      }
    end
    
    trait :classic do
      name { "Classic Theme" }
      color_scheme {
        {
          'primary' => '#374151',
          'secondary' => '#6b7280',
          'accent' => '#f59e0b',
          'dark' => '#111827',
          'light' => '#ffffff'
        }
      }
    end
  end
end 