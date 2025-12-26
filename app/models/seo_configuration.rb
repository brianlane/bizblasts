# frozen_string_literal: true

class SeoConfiguration < ApplicationRecord
  include TenantScoped

  belongs_to :business

  # Active Storage for social images
  has_one_attached :og_image
  has_one_attached :twitter_image

  # Validations
  validates :business_id, uniqueness: true
  validates :seo_score, numericality: { 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: 100 
  }, allow_nil: true

  # Callbacks
  after_initialize :set_defaults, if: :new_record?
  before_save :generate_auto_keywords, if: :should_regenerate_keywords?

  # Serialize array fields (for databases that don't support arrays natively)
  # PostgreSQL supports arrays natively, but this adds compatibility
  
  # Class methods
  class << self
    def for_business(business)
      find_or_create_by(business: business)
    end
  end

  # Instance methods
  
  # Generate meta title from template
  def render_meta_title(page_title: nil, service_name: nil, product_name: nil)
    template = meta_title_template.presence || default_title_template
    
    template
      .gsub('{{business_name}}', business.name)
      .gsub('{{page_title}}', page_title.to_s)
      .gsub('{{service_name}}', service_name.to_s)
      .gsub('{{product_name}}', product_name.to_s)
      .gsub('{{city}}', business.city.to_s)
      .gsub('{{state}}', business.state.to_s)
      .gsub('{{industry}}', business.industry&.humanize.to_s)
      .gsub(/\s*\|\s*\|/, ' |') # Clean up empty template vars
      .gsub(/\s*\|\s*$/, '') # Remove trailing separators
      .strip
  end

  # Generate meta description from template
  def render_meta_description(page_description: nil)
    template = meta_description_template.presence || default_description_template
    
    template
      .gsub('{{business_name}}', business.name)
      .gsub('{{description}}', page_description || business.description.to_s.truncate(100))
      .gsub('{{city}}', business.city.to_s)
      .gsub('{{state}}', business.state.to_s)
      .gsub('{{industry}}', business.industry&.humanize.to_s)
      .gsub('{{phone}}', business.phone.to_s)
      .strip
      .truncate(160)
  end

  # Get all keywords (auto + manual)
  def all_keywords
    ((auto_keywords || []) + (target_keywords || [])).uniq
  end

  # Get suggestion by priority
  def high_priority_suggestions
    (seo_suggestions || []).select { |s| s['priority'] == 'high' }
  end

  def medium_priority_suggestions
    (seo_suggestions || []).select { |s| s['priority'] == 'medium' }
  end

  def low_priority_suggestions
    (seo_suggestions || []).select { |s| s['priority'] == 'low' }
  end

  # Get keyword ranking for a specific keyword
  def ranking_for(keyword)
    (keyword_rankings || {})[keyword]
  end

  # Get estimated position for a keyword
  def estimated_position(keyword)
    ranking = ranking_for(keyword)
    ranking&.dig('position')
  end

  # Get ranking trend for a keyword
  def ranking_trend(keyword)
    ranking = ranking_for(keyword)
    ranking&.dig('trend') || 'unknown'
  end

  # SEO score breakdown with labels
  def score_breakdown_with_labels
    breakdown = seo_score_breakdown || {}
    {
      'Title Tag' => breakdown['title_score'] || 0,
      'Meta Description' => breakdown['description_score'] || 0,
      'Content Quality' => breakdown['content_score'] || 0,
      'Local SEO' => breakdown['local_seo_score'] || 0,
      'Technical SEO' => breakdown['technical_score'] || 0,
      'Image Optimization' => breakdown['image_score'] || 0,
      'Internal Linking' => breakdown['linking_score'] || 0,
      'Mobile Friendly' => breakdown['mobile_score'] || 0
    }
  end

  # SEO score color indicator
  def score_color
    case seo_score
    when 0..30 then 'red'
    when 31..60 then 'yellow'
    when 61..80 then 'blue'
    when 81..100 then 'green'
    else 'gray'
    end
  end

  # SEO score label
  def score_label
    case seo_score
    when 0..30 then 'Needs Improvement'
    when 31..60 then 'Fair'
    when 61..80 then 'Good'
    when 81..100 then 'Excellent'
    else 'Not Analyzed'
    end
  end

  # Mark keywords as needing regeneration
  # Call this externally when business attributes change
  def mark_keywords_stale!
    @keywords_stale = true
  end

  def keywords_stale?
    @keywords_stale == true
  end

  private

  def set_defaults
    self.meta_title_template ||= default_title_template
    self.meta_description_template ||= default_description_template
    self.seo_score ||= 0
    self.seo_score_breakdown ||= {}
    self.seo_suggestions ||= []
    self.keyword_rankings ||= {}
    self.auto_keywords ||= []
    self.target_keywords ||= []
    self.competitor_domains ||= []
    self.local_business_schema ||= {}
  end

  def default_title_template
    '{{business_name}} | {{page_title}} in {{city}}, {{state}}'
  end

  def default_description_template
    '{{business_name}} offers professional {{industry}} services in {{city}}, {{state}}. {{description}}'
  end

  def should_regenerate_keywords?
    return true if auto_keywords.blank?
    return true if keywords_stale?
    false
  end

  def generate_auto_keywords
    return unless business.present?
    
    keywords = []
    
    # Industry keywords
    if business.industry.present?
      industry_name = business.industry.humanize
      keywords << "#{industry_name} in #{business.city}"
      keywords << "#{business.city} #{industry_name}"
      keywords << "best #{industry_name} #{business.city}"
      keywords << "#{industry_name} near me"
      keywords << "#{industry_name} #{business.state}"
    end
    
    # Business name keywords
    if business.name.present?
      keywords << business.name
      keywords << "#{business.name} #{business.city}"
    end
    
    # Service keywords
    business.services.active.limit(10).each do |service|
      keywords << "#{service.name} #{business.city}"
      keywords << "#{service.name} near me"
    end
    
    # Location keywords
    keywords << "#{business.city} #{business.state}"
    keywords << "local business #{business.city}"
    
    self.auto_keywords = keywords.uniq.first(50) # Limit to 50 keywords
  end

  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id seo_score sitemap_enabled allow_indexing
       last_analysis_at last_keyword_check_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business]
  end
end

