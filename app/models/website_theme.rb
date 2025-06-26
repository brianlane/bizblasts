class WebsiteTheme < ApplicationRecord
  acts_as_tenant(:business)
  
  belongs_to :business
  
  validates :name, presence: true
  validates :color_scheme, :typography, :layout_config, presence: true
  validate :only_one_active_theme_per_business
  
  scope :active, -> { where(active: true) }
  
  # Default theme configuration
  DEFAULT_COLOR_SCHEME = {
    primary: '#1A5F7A',
    secondary: '#57C5B6', 
    accent: '#FF8C42',
    dark: '#333333',
    light: '#F8F9FA',
    success: '#28A745',
    warning: '#FFC107',
    error: '#DC3545',
    info: '#17A2B8'
  }.freeze
  
  DEFAULT_TYPOGRAPHY = {
    heading_font: 'Inter',
    body_font: 'Inter',
    font_size_base: '16px',
    font_size_small: '14px',
    font_size_large: '18px',
    line_height_base: '1.5',
    font_weight_normal: '400',
    font_weight_bold: '600'
  }.freeze
  
  DEFAULT_LAYOUT_CONFIG = {
    header_style: 'modern',
    sidebar_enabled: false,
    footer_style: 'simple',
    container_width: 'max-w-7xl',
    section_spacing: 'normal',
    border_radius: '8px'
  }.freeze
  
  def self.create_default_for_business(business)
    business.website_themes.create!(
      name: 'Default Theme',
      color_scheme: DEFAULT_COLOR_SCHEME,
      typography: DEFAULT_TYPOGRAPHY,
      layout_config: DEFAULT_LAYOUT_CONFIG,
      active: true
    )
  end
  
  def activate!
    transaction do
      business.website_themes.update_all(active: false)
      update!(active: true)
    end
  end
  
  def generate_css_variables
    variables = []
    
    # Color variables
    color_scheme.each do |key, value|
      variables << "--color-#{key.to_s.gsub('_', '-')}: #{value};"
    end
    
    # Typography variables  
    typography.each do |key, value|
      variables << "--#{key.to_s.gsub('_', '-')}: #{value};"
    end
    
    # Layout variables
    layout_config.each do |key, value|
      variables << "--layout-#{key.to_s.gsub('_', '-')}: #{value};" if value.is_a?(String)
    end
    
    ":root {\n  #{variables.join("\n  ")}\n}"
  end
  
  private
  
  def only_one_active_theme_per_business
    if active? && business.website_themes.where.not(id: id).where(active: true).exists?
      errors.add(:active, 'Only one theme can be active at a time')
    end
  end
end 