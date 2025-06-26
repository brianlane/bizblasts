class WebsiteTemplate < ApplicationRecord
  validates :name, :industry, :template_type, presence: true
  validates :structure, :default_theme, presence: true
  
  # Use the same industry mappings from Business model
  enum :industry, Business::SHOWCASE_INDUSTRY_MAPPINGS.keys.map(&:to_s).zip(
    Business::SHOWCASE_INDUSTRY_MAPPINGS.keys.map(&:to_s)
  ).to_h.merge('universal' => 'universal')
  
  enum :template_type, { 
    industry_specific: 0, 
    universal_template: 1 
  }
  
  scope :active, -> { where(active: true) }
  scope :for_industry, ->(industry) { where(industry: [industry, 'universal']) }
  scope :premium_only, -> { where(requires_premium: true) }
  scope :available_for_tier, ->(tier) do
    case tier
    when 'free'
      none # Free tier has no access to templates
    when 'standard'
      where(requires_premium: false)
    when 'premium'
      all
    else
      none
    end
  end
  
  def can_be_used_by?(business)
    return false unless business.standard_tier? || business.premium_tier?
    return false if requires_premium? && !business.premium_tier?
    
    industry == 'universal' || industry == business.industry
  end
  
  def preview_image_url_or_default
    preview_image_url.presence || "/assets/template-previews/#{industry}-default.jpg"
  end
  
  # Default page structure for templates
  def self.default_page_structure
    {
      pages: [
        {
          title: 'Home',
          slug: 'home',
          page_type: 'home',
          sections: [
            { type: 'hero_banner', position: 0 },
            { type: 'service_list', position: 1 },
            { type: 'testimonial', position: 2 },
            { type: 'contact_form', position: 3 }
          ]
        },
        {
          title: 'About',
          slug: 'about', 
          page_type: 'about',
          sections: [
            { type: 'text', position: 0 },
            { type: 'team_showcase', position: 1 }
          ]
        },
        {
          title: 'Services',
          slug: 'services',
          page_type: 'services', 
          sections: [
            { type: 'service_list', position: 0 }
          ]
        },
        {
          title: 'Contact',
          slug: 'contact',
          page_type: 'contact',
          sections: [
            { type: 'contact_form', position: 0 },
            { type: 'map_location', position: 1 }
          ]
        }
      ]
    }
  end
  
  def self.create_industry_template(industry_key, theme_colors = {})
    industry_name = Business::SHOWCASE_INDUSTRY_MAPPINGS[industry_key.to_sym]
    return nil unless industry_name
    
    base_theme = WebsiteTheme::DEFAULT_COLOR_SCHEME.merge(theme_colors)
    
    create!(
      name: "#{industry_name} Professional",
      industry: industry_key.to_s,
      template_type: 'industry_specific',
      description: "Professional template designed specifically for #{industry_name} businesses",
      structure: default_page_structure,
      default_theme: {
        color_scheme: base_theme,
        typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
        layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG
      },
      requires_premium: false,
      active: true
    )
  end
end 