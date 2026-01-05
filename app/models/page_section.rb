class PageSection < ApplicationRecord
  belongs_to :page
  # Remove has_rich_text :content since we're using JSON instead
  # has_rich_text :content  # Add ActionText support

  # Gallery associations
  has_many :gallery_photos, -> { order(:position) },
           as: :owner,
           dependent: :destroy
  has_one_attached :gallery_video

  validates :section_type, presence: true
  validates :content, presence: true, unless: :content_optional_section?
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Gallery video validation
  validates :gallery_video,
            content_type: { in: %w[video/mp4 video/webm video/quicktime video/x-msvideo],
                            message: 'must be a valid video format' },
            size: { less_than: 50.megabytes },
            if: -> { section_type == 'gallery' && gallery_video.attached? }

  enum :section_type, {
    header: 0,
    text: 1,
    image: 2,
    gallery: 3,
    contact_form: 4,
    service_list: 5,
    testimonial: 6,
    cta: 7,
    custom: 8,
    # New section types for enhanced customization
    hero_banner: 9,
    product_grid: 10,
    team_showcase: 11,
    pricing_table: 12,
    faq_section: 13,
    social_media: 14,
    video_embed: 15,
    map_location: 16,
    newsletter_signup: 17,
    product_list: 18,
    estimate_cta: 19,
    rental_list: 20
  }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position) }
  scope :by_type, ->(type) { where(section_type: type) }

  before_save :set_default_config
  after_commit :process_gallery_video, if: -> {
    section_type == 'gallery' && gallery_video.attached? && saved_change_to_id?
  }
  
  def background_color
    background_settings&.dig('color') || '#ffffff'
  end
  
  def has_animation?
    animation_type.present?
  end
  
  def css_classes
    classes = [custom_css_classes]
    classes << "animate-#{animation_type}" if has_animation?
    classes << "section-#{section_type}"
    classes.compact.join(' ')
  end
  
  def render_content_for(business)
    case section_type
    when 'service_list'
      business.services.active.limit(section_config&.dig('limit') || 6)
    when 'product_list'
      business.products.active.limit(section_config&.dig('limit') || 8)
    when 'rental_list'
      business.products.rentals.active.limit(section_config&.dig('limit') || 6)
    when 'product_grid'
      business.products.active.limit(section_config&.dig('limit') || 8)
    when 'team_showcase'
      business.staff_members.active.limit(section_config&.dig('limit') || 4)
    else
      content
    end
  end
  
  # For structured sections like hero_banner, get content as a hash
  # Now this will work properly with JSON storage
  def content_data
    return {} unless content.present?

    case content
    when Hash
      content
    when String
      begin
        JSON.parse(content)
      rescue JSON::ParserError
        {}
      end
    else
      {}
    end
  end

  # Gallery configuration helpers
  def gallery_layout
    section_config&.dig('layout') || 'grid'
  end

  def gallery_columns
    section_config&.dig('columns') || 3
  end

  def gallery_photo_source_mode
    section_config&.dig('photo_source_mode') || 'business'
  end

  # Get photos to display based on source mode
  def display_photos
    case gallery_photo_source_mode
    when 'own'
      gallery_photos.by_position.limit(50)
    when 'business'
      page.business.gallery_photos.business_owned.by_position.limit(50)
    when 'mixed'
      section_photos = gallery_photos.by_position.to_a
      business_photos = page.business.gallery_photos.business_owned
                          .by_position
                          .where.not(id: section_photos.map(&:id))
                          .limit(50 - section_photos.size)
      section_photos + business_photos.to_a
    end
  end

  private
  
  # Content is optional for sections that generate their own content dynamically
  def content_optional_section?
    %w[contact_form service_list product_list product_grid rental_list team_showcase pricing_table map_location newsletter_signup gallery].include?(section_type)
  end
  
  def set_default_config
    self.section_config ||= default_config_for_type
    self.background_settings ||= { 'color' => '#ffffff', 'image' => nil }
  end
  
  def default_config_for_type
    case section_type
    when 'hero_banner'
      { 'height' => 'large', 'text_alignment' => 'center', 'overlay' => true }
    when 'service_list'
      { 'layout' => 'grid', 'columns' => 3, 'limit' => 6 }
    when 'product_list'
      { 'layout' => 'grid', 'columns' => 4, 'limit' => 8 }
    when 'rental_list'
      { 'layout' => 'grid', 'columns' => 3, 'limit' => 6 }
    when 'product_grid'
      { 'layout' => 'grid', 'columns' => 4, 'limit' => 8 }
    when 'testimonial'
      { 'layout' => 'carousel', 'limit' => 5 }
    when 'team_showcase'
      { 'layout' => 'grid', 'columns' => 4, 'limit' => 4 }
    when 'pricing_table'
      { 'layout' => 'grid', 'columns' => 3 }
    when 'gallery'
      {
        'layout' => 'grid',
        'columns' => 3,
        'photo_source_mode' => 'business',
        'show_video' => false,
        'video_position' => 'before',
        'video_title' => '',
        'video_autoplay' => false,
        'show_hover_effects' => true,
        'show_photo_titles' => true,
        'max_photos' => 50
      }
    else
      {}
    end
  end

  # Process gallery video after commit
  def process_gallery_video
    ProcessGalleryVideoJob.perform_later(id, 'PageSection')
  end
end
