class WebsiteTemplateService
  class TemplateApplicationError < StandardError; end
  
  def self.apply_template(business, template_id, user = nil)
    return false unless business.standard_tier? || business.premium_tier?
    
    template = WebsiteTemplate.find(template_id)
    
    unless template.can_be_used_by?(business)
      raise TemplateApplicationError, "Template not available for your business tier or industry"
    end
    
    business.transaction do
      # Create/update theme based on template
      theme = create_or_update_theme(business, template)
      
      # Create pages from template structure
      create_pages_from_template(business, template, user)
      
      # Mark template as applied
      business.update!(template_applied: template.name)
    end
    
    true
  rescue => e
    Rails.logger.error "Failed to apply template #{template_id} to business #{business.id}: #{e.message}"
    false
  end
  
  def self.create_default_theme_for_business(business)
    return false if business.free_tier?
    
    WebsiteTheme.create_default_for_business(business)
  end
  
  def self.available_templates_for_business(business)
    return WebsiteTemplate.none if business.free_tier?
    
    WebsiteTemplate.active
                   .available_for_tier(business.tier)
                   .for_industry(business.industry)
                   .order(:template_type, :name)
  end
  
  def self.preview_template(template_id, business_id = nil)
    template = WebsiteTemplate.find(template_id)
    business = Business.find(business_id) if business_id
    
    {
      template: template,
      preview_data: generate_preview_data(template, business),
      theme_css: generate_theme_css(template.default_theme)
    }
  end
  
  private
  
  def self.create_or_update_theme(business, template)
    theme = business.website_themes.active.first || business.website_themes.build
    
    theme.update!(
      name: template.name,
      color_scheme: template.default_theme['color_scheme'] || WebsiteTheme::DEFAULT_COLOR_SCHEME,
      typography: template.default_theme['typography'] || WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: template.default_theme['layout_config'] || WebsiteTheme::DEFAULT_LAYOUT_CONFIG,
      active: true
    )
    
    theme
  end
  
  def self.create_pages_from_template(business, template, user)
    template.structure['pages'].each do |page_data|
      create_page_from_template(business, page_data, user)
    end
  end
  
  def self.create_page_from_template(business, page_data, user)
    # Check if page already exists
    existing_page = business.pages.find_by(slug: page_data['slug'])
    
    if existing_page
      # Update existing page instead of creating new one
      page = existing_page
    else
      page = business.pages.build
    end
    
    page.update!(
      title: page_data['title'],
      slug: page_data['slug'],
      page_type: page_data['page_type'],
      status: :published,
      published_at: Time.current,
      show_in_menu: page_data.fetch('show_in_menu', true),
      menu_order: page_data.fetch('menu_order', 0),
      seo_title: page_data['seo_title'] || page_data['title'],
      meta_description: page_data['meta_description'] || "#{page_data['title']} - #{business.name}"
    )
    
    # Remove existing sections if updating
    page.page_sections.destroy_all if existing_page
    
    # Create sections from template
    page_data['sections']&.each do |section_data|
      create_section_from_template(page, section_data)
    end
    
    # Create initial version
    PageVersion.create_from_page(page, user, "Created from template: #{page_data['title']}")
    
    page
  end
  
  def self.create_section_from_template(page, section_data)
    page.page_sections.create!(
      section_type: section_data['type'],
      position: section_data['position'],
      content: default_content_for_section(section_data['type'], page.business),
      section_config: section_data['config'] || {},
      active: true
    )
  end
  
  def self.default_content_for_section(section_type, business)
    case section_type
    when 'hero_banner'
      "<h1>Welcome to #{business.name}</h1><p>#{business.description}</p>"
    when 'text'
      "<h2>About #{business.name}</h2><p>#{business.description}</p>"
    when 'contact_form'
      "<h2>Contact Us</h2><p>Get in touch with #{business.name} today.</p>"
    when 'testimonial'
      "<h2>What Our Customers Say</h2><p>We're proud to serve our community with excellence.</p>"
    when 'cta'
      "<h2>Ready to Get Started?</h2><p>Contact #{business.name} today for a consultation.</p>"
    when 'faq_section'
      "<h2>Frequently Asked Questions</h2><p>Find answers to common questions about our services.</p>"
    when 'team_showcase'
      "<h2>Meet Our Team</h2><p>Get to know the professionals at #{business.name}.</p>"
    when 'pricing_table'
      "<h2>Our Pricing</h2><p>Transparent pricing for all our services.</p>"
    else
      "<h2>#{section_type.humanize}</h2><p>Content for #{business.name}.</p>"
    end
  end
  
  def self.generate_preview_data(template, business)
    {
      business_name: business&.name || 'Your Business Name',
      business_description: business&.description || 'Your business description will appear here.',
      industry: template.industry,
      pages: template.structure['pages'].map { |p| p['title'] }
    }
  end
  
  def self.generate_theme_css(theme_data)
    return '' unless theme_data

    variables = []

    if theme_data['color_scheme']
      theme_data['color_scheme'].each do |key, value|
        sanitized_key = CssSanitizer.sanitize_css_property_name(key)
        sanitized_value = CssSanitizer.sanitize_css_value(value)
        variables << "--color-#{sanitized_key}: #{sanitized_value};" if sanitized_key.present? && sanitized_value.present?
      end
    end

    if theme_data['typography']
      theme_data['typography'].each do |key, value|
        sanitized_key = CssSanitizer.sanitize_css_property_name(key)
        sanitized_value = CssSanitizer.sanitize_css_value(value)
        variables << "--#{sanitized_key}: #{sanitized_value};" if sanitized_key.present? && sanitized_value.present?
      end
    end

    ":root { #{variables.join(' ')} }"
  end
end 