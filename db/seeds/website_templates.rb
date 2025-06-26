# Website Templates Seeding

puts "Creating website templates..."

# Universal templates (cross-industry)
universal_templates = [
  {
    name: 'Modern Minimal',
    description: 'Clean and minimalist design perfect for any modern business',
    colors: { primary: '#2563eb', secondary: '#64748b', accent: '#f59e0b' }
  },
  {
    name: 'Bold & Creative',
    description: 'Eye-catching design for creative and innovative businesses',
    colors: { primary: '#dc2626', secondary: '#7c3aed', accent: '#f59e0b' }
  },
  {
    name: 'Professional Corporate',
    description: 'Traditional corporate design for established businesses',
    colors: { primary: '#1e40af', secondary: '#374151', accent: '#059669' }
  },
  {
    name: 'Warm & Friendly',
    description: 'Welcoming design that builds trust and comfort',
    colors: { primary: '#ea580c', secondary: '#0d9488', accent: '#fbbf24' }
  },
  {
    name: 'Tech Forward',
    description: 'Sleek and modern for technology-focused businesses',
    colors: { primary: '#4338ca', secondary: '#06b6d4', accent: '#8b5cf6' }
  },
  {
    name: 'Classic Elegant',
    description: 'Timeless elegance for luxury and premium services',
    colors: { primary: '#374151', secondary: '#6b7280', accent: '#d97706' }
  },
  {
    name: 'Vibrant & Fun',
    description: 'Energetic design for entertainment and lifestyle businesses',
    colors: { primary: '#ec4899', secondary: '#10b981', accent: '#f59e0b' }
  },
  {
    name: 'Clean & Simple',
    description: 'Straightforward design focused on clarity and usability',
    colors: { primary: '#059669', secondary: '#6b7280', accent: '#3b82f6' }
  },
  {
    name: 'Artistic & Unique',
    description: 'Creative and distinctive design for artistic businesses',
    colors: { primary: '#7c3aed', secondary: '#ec4899', accent: '#f59e0b' }
  },
  {
    name: 'Premium Luxury',
    description: 'High-end design for luxury brands and premium services',
    colors: { primary: '#1f2937', secondary: '#6b7280', accent: '#d97706' },
    premium: true
  }
]

# Create universal templates
universal_templates.each do |template_data|
  template = WebsiteTemplate.find_or_create_by(
    name: template_data[:name],
    industry: 'universal'
  ) do |t|
    t.template_type = 'universal_template'
    t.description = template_data[:description]
    t.structure = WebsiteTemplate.default_page_structure
    t.default_theme = {
      color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME.merge(template_data[:colors]),
      typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
    }
    t.requires_premium = template_data[:premium] || false
    t.active = true
  end
  
  puts "Created universal template: #{template.name}"
end

# Industry-specific color schemes
industry_color_schemes = {
  'hair_salons' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#f59e0b' },
  'massage_therapy' => { primary: '#059669', secondary: '#0d9488', accent: '#fbbf24' },
  'pet_grooming' => { primary: '#f59e0b', secondary: '#ec4899', accent: '#10b981' },
  'auto_repair' => { primary: '#374151', secondary: '#dc2626', accent: '#f59e0b' },
  'hvac_services' => { primary: '#2563eb', secondary: '#64748b', accent: '#dc2626' },
  'plumbing' => { primary: '#2563eb', secondary: '#059669', accent: '#f59e0b' },
  'landscaping' => { primary: '#059669', secondary: '#84cc16', accent: '#d97706' },
  'pool_services' => { primary: '#0ea5e9', secondary: '#06b6d4', accent: '#f59e0b' },
  'cleaning_services' => { primary: '#0ea5e9', secondary: '#64748b', accent: '#10b981' },
  'tutoring' => { primary: '#7c3aed', secondary: '#3b82f6', accent: '#f59e0b' },
  'personal_training' => { primary: '#dc2626', secondary: '#ea580c', accent: '#84cc16' },
  'photography' => { primary: '#374151', secondary: '#6b7280', accent: '#ec4899' },
  'web_design' => { primary: '#4338ca', secondary: '#06b6d4', accent: '#8b5cf6' },
  'consulting' => { primary: '#1e40af', secondary: '#374151', accent: '#059669' },
  'accounting' => { primary: '#374151', secondary: '#1e40af', accent: '#059669' },
  'legal_services' => { primary: '#1f2937', secondary: '#374151', accent: '#d97706' },
  'dental_care' => { primary: '#0ea5e9', secondary: '#64748b', accent: '#10b981' },
  'veterinary' => { primary: '#059669', secondary: '#f59e0b', accent: '#ec4899' },
  'handyman_service' => { primary: '#d97706', secondary: '#374151', accent: '#dc2626' },
  'painting' => { primary: '#ec4899', secondary: '#7c3aed', accent: '#f59e0b' },
  'roofing' => { primary: '#374151', secondary: '#dc2626', accent: '#f59e0b' },
  'carpet_cleaning' => { primary: '#0ea5e9', secondary: '#10b981', accent: '#f59e0b' },
  'pest_control' => { primary: '#059669', secondary: '#374151', accent: '#f59e0b' },
  'beauty_spa' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#fbbf24' },
  'moving_services' => { primary: '#d97706', secondary: '#374151', accent: '#2563eb' },
  'catering' => { primary: '#ea580c', secondary: '#f59e0b', accent: '#059669' },
  'dj_services' => { primary: '#7c3aed', secondary: '#ec4899', accent: '#f59e0b' },
  'event_planning' => { primary: '#ec4899', secondary: '#7c3aed', accent: '#fbbf24' },
  'tax_preparation' => { primary: '#374151', secondary: '#1e40af', accent: '#059669' },
  'it_support' => { primary: '#4338ca', secondary: '#06b6d4', accent: '#64748b' },
  
  # Experiences
  'yoga_classes' => { primary: '#059669', secondary: '#8b5cf6', accent: '#fbbf24' },
  'escape_rooms' => { primary: '#7c3aed', secondary: '#374151', accent: '#f59e0b' },
  'wine_tasting' => { primary: '#7c2d12', secondary: '#dc2626', accent: '#d97706' },
  'cooking_classes' => { primary: '#ea580c', secondary: '#f59e0b', accent: '#059669' },
  'art_studios' => { primary: '#ec4899', secondary: '#7c3aed', accent: '#f59e0b' },
  'dance_studios' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#f59e0b' },
  'music_lessons' => { primary: '#7c3aed', secondary: '#3b82f6', accent: '#f59e0b' },
  'adventure_tours' => { primary: '#059669', secondary: '#d97706', accent: '#dc2626' },
  'boat_charters' => { primary: '#0ea5e9', secondary: '#06b6d4', accent: '#f59e0b' },
  'helicopter_tours' => { primary: '#4338ca', secondary: '#64748b', accent: '#f59e0b' },
  'food_tours' => { primary: '#ea580c', secondary: '#f59e0b', accent: '#059669' },
  'ghost_tours' => { primary: '#374151', secondary: '#6b7280', accent: '#7c3aed' },
  'museums' => { primary: '#374151', secondary: '#6b7280', accent: '#d97706' },
  'aquariums' => { primary: '#0ea5e9', secondary: '#06b6d4', accent: '#059669' },
  'theme_parks' => { primary: '#ec4899', secondary: '#f59e0b', accent: '#10b981' },
  'zip_lines' => { primary: '#059669', secondary: '#84cc16', accent: '#f59e0b' },
  'paintball' => { primary: '#dc2626', secondary: '#374151', accent: '#f59e0b' },
  'laser_tag' => { primary: '#4338ca', secondary: '#7c3aed', accent: '#f59e0b' },
  'bowling_alleys' => { primary: '#d97706', secondary: '#dc2626', accent: '#2563eb' },
  'mini_golf' => { primary: '#84cc16', secondary: '#059669', accent: '#f59e0b' },
  'go_kart_racing' => { primary: '#dc2626', secondary: '#f59e0b', accent: '#374151' },
  'arcades' => { primary: '#7c3aed', secondary: '#ec4899', accent: '#f59e0b' },
  'comedy_clubs' => { primary: '#f59e0b', secondary: '#ec4899', accent: '#7c3aed' },
  'theater_shows' => { primary: '#7c2d12', secondary: '#d97706', accent: '#dc2626' },
  'concerts' => { primary: '#7c3aed', secondary: '#ec4899', accent: '#f59e0b' },
  'festivals' => { primary: '#ec4899', secondary: '#f59e0b', accent: '#10b981' },
  'workshops' => { primary: '#7c3aed', secondary: '#3b82f6', accent: '#f59e0b' },
  'seminars' => { primary: '#1e40af', secondary: '#374151', accent: '#059669' },
  'retreats' => { primary: '#059669', secondary: '#8b5cf6', accent: '#fbbf24' },
  'spa_days' => { primary: '#8b5cf6', secondary: '#ec4899', accent: '#fbbf24' },
  
  # Products
  'boutiques' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#f59e0b' },
  'jewelry_stores' => { primary: '#374151', secondary: '#6b7280', accent: '#d97706' },
  'electronics' => { primary: '#4338ca', secondary: '#64748b', accent: '#06b6d4' },
  'bookstores' => { primary: '#7c2d12', secondary: '#d97706', accent: '#059669' },
  'art_galleries' => { primary: '#374151', secondary: '#6b7280', accent: '#ec4899' },
  'craft_stores' => { primary: '#ec4899', secondary: '#f59e0b', accent: '#7c3aed' },
  'antique_shops' => { primary: '#7c2d12', secondary: '#d97706', accent: '#374151' },
  'toy_stores' => { primary: '#ec4899', secondary: '#f59e0b', accent: '#10b981' },
  'sports_equipment' => { primary: '#dc2626', secondary: '#2563eb', accent: '#f59e0b' },
  'outdoor_gear' => { primary: '#059669', secondary: '#d97706', accent: '#374151' },
  'home_decor' => { primary: '#6b7280', secondary: '#d97706', accent: '#ec4899' },
  'furniture_stores' => { primary: '#7c2d12', secondary: '#d97706', accent: '#374151' },
  'bakeries' => { primary: '#ea580c', secondary: '#f59e0b', accent: '#7c2d12' },
  'coffee_shops' => { primary: '#7c2d12', secondary: '#d97706', accent: '#f59e0b' },
  'wine_shops' => { primary: '#7c2d12', secondary: '#dc2626', accent: '#d97706' },
  'specialty_foods' => { primary: '#ea580c', secondary: '#059669', accent: '#f59e0b' },
  'cosmetics' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#fbbf24' },
  'perfume_shops' => { primary: '#8b5cf6', secondary: '#ec4899', accent: '#f59e0b' },
  'pet_supplies' => { primary: '#f59e0b', secondary: '#059669', accent: '#ec4899' },
  'plant_nurseries' => { primary: '#059669', secondary: '#84cc16', accent: '#d97706' },
  'garden_centers' => { primary: '#84cc16', secondary: '#059669', accent: '#d97706' },
  'hardware_stores' => { primary: '#374151', secondary: '#dc2626', accent: '#f59e0b' },
  'music_stores' => { primary: '#7c3aed', secondary: '#3b82f6', accent: '#f59e0b' },
  'gift_shops' => { primary: '#ec4899', secondary: '#f59e0b', accent: '#7c3aed' },
  'souvenir_shops' => { primary: '#f59e0b', secondary: '#ec4899', accent: '#059669' },
  'thrift_stores' => { primary: '#059669', secondary: '#d97706', accent: '#7c3aed' },
  'clothing' => { primary: '#374151', secondary: '#ec4899', accent: '#f59e0b' },
  'local_artisans' => { primary: '#7c3aed', secondary: '#ec4899', accent: '#d97706' },
  'handmade_goods' => { primary: '#d97706', secondary: '#ec4899', accent: '#059669' },
  'farmers_markets' => { primary: '#84cc16', secondary: '#059669', accent: '#f59e0b' }
}

# Create industry-specific templates
Business::SHOWCASE_INDUSTRY_MAPPINGS.each do |industry_key, industry_name|
  next if industry_key == :other
  
  colors = industry_color_schemes[industry_key.to_s] || WebsiteTheme::DEFAULT_COLOR_SCHEME
  
  template = WebsiteTemplate.find_or_create_by(
    industry: industry_key.to_s,
    template_type: 'industry_specific'
  ) do |t|
    t.name = "#{industry_name} Professional"
    t.description = "Professional template designed specifically for #{industry_name} businesses"
    t.structure = WebsiteTemplate.default_page_structure
    t.default_theme = {
      color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME.merge(colors),
      typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
    }
    t.requires_premium = false
    t.active = true
  end
  
  puts "Created industry template: #{template.name}"
end

puts "Finished creating #{WebsiteTemplate.count} website templates" 