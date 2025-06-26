#!/usr/bin/env ruby

# Load Rails environment
require_relative 'config/environment'

puts "Starting diverse template creation..."

# Define different structure patterns
structures = {
  minimalist: {
    pages: [
      { title: 'Home', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'feature_showcase', position: 1 },
        { type: 'contact_form', position: 2 }
      ]},
      { title: 'About', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 }
      ]},
      { title: 'Contact', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'business_hours', position: 1 }
      ]}
    ]
  },
  
  service_focused: {
    pages: [
      { title: 'Welcome', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'service_list', position: 1 },
        { type: 'call_to_action', position: 2 }
      ]},
      { title: 'Our Services', slug: 'services', page_type: 'services', sections: [
        { type: 'service_list', position: 0 },
        { type: 'pricing_table', position: 1 },
        { type: 'testimonial', position: 2 }
      ]},
      { title: 'About', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 },
        { type: 'team_showcase', position: 1 }
      ]},
      { title: 'Get Quote', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'business_hours', position: 1 }
      ]}
    ]
  },
  
  product_focused: {
    pages: [
      { title: 'Welcome', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'product_list', position: 1 },
        { type: 'call_to_action', position: 2 }
      ]},
      { title: 'Our Products', slug: 'products', page_type: 'products', sections: [
        { type: 'product_list', position: 0 },
        { type: 'feature_showcase', position: 1 },
        { type: 'testimonial', position: 2 }
      ]},
      { title: 'About', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 },
        { type: 'company_values', position: 1 }
      ]},
      { title: 'Shop', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'business_hours', position: 1 }
      ]}
    ]
  },
  
  creative_portfolio: {
    pages: [
      { title: 'Home', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'portfolio_gallery', position: 1 },
        { type: 'testimonial', position: 2 }
      ]},
      { title: 'Portfolio', slug: 'portfolio', page_type: 'portfolio', sections: [
        { type: 'portfolio_gallery', position: 0 }
      ]},
      { title: 'Services', slug: 'services', page_type: 'services', sections: [
        { type: 'service_list', position: 0 },
        { type: 'feature_showcase', position: 1 }
      ]},
      { title: 'About', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 },
        { type: 'team_showcase', position: 1 }
      ]},
      { title: 'Contact', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'social_links', position: 1 }
      ]}
    ]
  },
  
  premium_corporate: {
    pages: [
      { title: 'Home', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'stats_counter', position: 1 },
        { type: 'feature_showcase', position: 2 },
        { type: 'call_to_action', position: 3 }
      ]},
      { title: 'Services', slug: 'services', page_type: 'services', sections: [
        { type: 'service_list', position: 0 },
        { type: 'pricing_table', position: 1 }
      ]},
      { title: 'About', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 },
        { type: 'company_values', position: 1 },
        { type: 'team_showcase', position: 2 }
      ]},
      { title: 'Case Studies', slug: 'case-studies', page_type: 'case_studies', sections: [
        { type: 'case_study_list', position: 0 },
        { type: 'testimonial', position: 1 }
      ]},
      { title: 'Testimonials', slug: 'testimonials', page_type: 'testimonials', sections: [
        { type: 'testimonial', position: 0 },
        { type: 'stats_counter', position: 1 }
      ]},
      { title: 'Contact', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'map_location', position: 1 },
        { type: 'business_hours', position: 2 }
      ]}
    ]
  },
  
  community_focused: {
    pages: [
      { title: 'Welcome', slug: 'home', page_type: 'home', sections: [
        { type: 'hero_banner', position: 0 },
        { type: 'company_values', position: 1 },
        { type: 'stats_counter', position: 2 },
        { type: 'social_links', position: 3 }
      ]},
      { title: 'What We Do', slug: 'services', page_type: 'services', sections: [
        { type: 'service_list', position: 0 },
        { type: 'feature_showcase', position: 1 }
      ]},
      { title: 'Our Story', slug: 'about', page_type: 'about', sections: [
        { type: 'text', position: 0 },
        { type: 'team_showcase', position: 1 },
        { type: 'testimonial', position: 2 }
      ]},
      { title: 'Connect', slug: 'contact', page_type: 'contact', sections: [
        { type: 'contact_form', position: 0 },
        { type: 'map_location', position: 1 },
        { type: 'social_links', position: 2 }
      ]}
    ]
  }
}

# Industry color schemes
industry_colors = {
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
  'boutiques' => { primary: '#ec4899', secondary: '#8b5cf6', accent: '#f59e0b' },
  'electronics' => { primary: '#4338ca', secondary: '#64748b', accent: '#06b6d4' },
  'bakeries' => { primary: '#ea580c', secondary: '#f59e0b', accent: '#7c2d12' },
  'coffee_shops' => { primary: '#7c2d12', secondary: '#d97706', accent: '#f59e0b' }
}

# Product-focused industries
product_industries = [
  'boutiques', 'jewelry_stores', 'electronics', 'bookstores', 'art_galleries', 
  'craft_stores', 'antique_shops', 'toy_stores', 'sports_equipment', 'outdoor_gear',
  'home_decor', 'furniture_stores', 'bakeries', 'coffee_shops', 'wine_shops',
  'specialty_foods', 'cosmetics', 'perfume_shops', 'pet_supplies', 'plant_nurseries',
  'garden_centers', 'hardware_stores', 'music_stores', 'gift_shops', 'souvenir_shops',
  'thrift_stores', 'clothing', 'local_artisans', 'handmade_goods', 'farmers_markets'
]

structure_names = structures.keys
updated_count = 0

# Universal templates with diverse structures
universal_templates = [
  { name: 'Modern Minimal', colors: { primary: '#2563eb', secondary: '#64748b', accent: '#f59e0b' }},
  { name: 'Bold & Creative', colors: { primary: '#dc2626', secondary: '#7c3aed', accent: '#f59e0b' }},
  { name: 'Professional Corporate', colors: { primary: '#1e40af', secondary: '#374151', accent: '#059669' }},
  { name: 'Warm & Friendly', colors: { primary: '#ea580c', secondary: '#0d9488', accent: '#fbbf24' }},
  { name: 'E-commerce Modern', colors: { primary: '#3b82f6', secondary: '#6b7280', accent: '#f59e0b' }, product_focused: true},
  { name: 'Retail Showcase', colors: { primary: '#ec4899', secondary: '#8b5cf6', accent: '#f59e0b' }, product_focused: true}
]

universal_templates.each_with_index do |template_data, index|
  # Select structure based on template characteristics
  structure_key = case template_data[:name].downcase
  when /minimal|clean|simple/
    :minimalist
  when /creative|bold/
    :creative_portfolio  
  when /corporate|professional/
    :premium_corporate
  when /warm|friendly/
    :community_focused
  when /ecommerce|retail|modern/
    template_data[:product_focused] ? :product_focused : :service_focused
  else
    structure_names[index % structure_names.length]
  end
  
  # Adjust structure for product-focused templates
  if template_data[:product_focused] && structure_key == :service_focused
    structure = structures[:product_focused].deep_dup
  elsif template_data[:product_focused] && structures[structure_key]
    # Modify existing structure to be product-focused
    structure = structures[structure_key].deep_dup
    structure[:pages].each do |page|
      page[:sections].each do |section|
        if section[:type] == 'service_list'
          section[:type] = 'product_list'
        end
      end
    end
  else
    structure = structures[structure_key]
  end
  
  template = WebsiteTemplate.create!(
    name: template_data[:name],
    industry: 'universal',
    template_type: 'universal_template',
    description: "#{template_data[:name]} template perfect for any business",
    structure: structure,
    default_theme: {
      color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME.merge(template_data[:colors]),
      typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
    },
    requires_premium: false,
    active: true
  )
  
  updated_count += 1
  puts "Created universal template: #{template.name} with #{structure_key} structure (#{structure[:pages].length} pages)"
end

# Create industry-specific templates with diverse structures
Business::SHOWCASE_INDUSTRY_MAPPINGS.each_with_index do |(industry_key, industry_name), index|
  next if industry_key == :other
  
  colors = industry_colors[industry_key.to_s] || { primary: '#2563eb', secondary: '#64748b', accent: '#f59e0b' }
  is_product_focused = product_industries.include?(industry_key.to_s)
  
  # Assign structure based on template characteristics and variety
  structure_key = case industry_name.downcase
  when /creative|artistic|photography|design/
    :creative_portfolio  
  when /premium|luxury|legal|corporate|consulting/
    :premium_corporate
  when /community|spa|yoga|local/
    :community_focused
  when /boutique|retail|shop|store/
    is_product_focused ? :product_focused : :service_focused
  else
    # Use index to distribute evenly across remaining structures
    structure_names[index % structure_names.length]
  end
  
  # Get the base structure
  if is_product_focused && structure_key == :service_focused
    structure = structures[:product_focused].deep_dup
  elsif is_product_focused && structures[structure_key]
    # Modify existing structure to be product-focused
    structure = structures[structure_key].deep_dup
    structure[:pages].each do |page|
      page[:sections].each do |section|
        if section[:type] == 'service_list'
          section[:type] = 'product_list'
        end
      end
      # Add/modify product-specific pages
      if page[:page_type] == 'services'
        page[:title] = 'Products'
        page[:slug] = 'products'
        page[:page_type] = 'products'
      end
    end
  else
    structure = structures[structure_key]
  end
  
  template_names = [
    "#{industry_name} Professional",
    "#{industry_name} Modern", 
    "#{industry_name} Classic",
    "#{industry_name} Premium",
    "#{industry_name} Creative"
  ]
  
  template_name = template_names[index % template_names.length]
  
  template = WebsiteTemplate.create!(
    name: template_name,
    industry: industry_key.to_s,
    template_type: 'industry_specific',
    description: "Professional template designed specifically for #{industry_name} businesses",
    structure: structure,
    default_theme: {
      color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME.merge(colors),
      typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
    },
    requires_premium: false,
    active: true
  )
  
  updated_count += 1
  puts "Updated template #{template.id}: #{template.name} with #{structure_key} structure (#{structure[:pages].length} pages) #{is_product_focused ? '[Product-focused]' : '[Service-focused]'}"
  
  # Small delay to prevent overwhelming the database
  sleep(0.05) if updated_count % 10 == 0
end

puts "\nCompleted creating #{updated_count} templates with unique structures!"
puts "Templates now have genuinely different page layouts, section arrangements, and structures."

# Show summary
structure_counts = {}
WebsiteTemplate.all.each do |template|
  page_count = template.structure[:pages].length
  structure_type = case page_count
  when 3
    "Minimalist"
  when 4
    "Service/Product"
  when 5
    "Portfolio"
  when 6
    "Corporate"
  else
    "Community"
  end
  structure_counts[structure_type] ||= 0
  structure_counts[structure_type] += 1
end

puts "\nStructure distribution:"
structure_counts.each do |type, count|
  puts "  #{type}: #{count} templates"
end 