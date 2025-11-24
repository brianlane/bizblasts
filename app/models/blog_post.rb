class BlogPost < ApplicationRecord
  # Featured image attachment
  has_one_attached :featured_image do |attachable|
    attachable.variant :thumb, resize_to_limit: [600, 400]
    attachable.variant :card, resize_to_limit: [800, 400]
    attachable.variant :medium, resize_to_limit: [800, 800] 
    attachable.variant :large, resize_to_limit: [1200, 1200]
  end

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :excerpt, presence: true
  validates :content, presence: true
  validates :category, inclusion: { in: %w[release feature tutorial announcement business-tips spotlight platform-updates] }
  
  # Image validations - Updated for HEIC support
  validates :featured_image, **FileUploadSecurity.image_validation_options

  def self.ransackable_attributes(auth_object = nil)
    ["author_email", "author_name", "category", "content", "created_at", "excerpt", "featured_image_url", "id", "id_value", "published", "published_at", "release_date", "slug", "title", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  # Virtual attribute for removing featured image
  attr_accessor :remove_featured_image
  
  before_validation :generate_slug, if: -> { slug.blank? && title.present? }
  before_save :set_published_at, if: -> { published && (published_changed? || published_at.blank?) }
  before_save :handle_featured_image_removal
  after_commit :send_publication_notifications, if: -> { saved_change_to_published? && published? }

  scope :published, -> { where(published: true).where.not(published_at: nil) }
  scope :recent, -> { order(published_at: :desc) }
  scope :by_category, ->(category) { where(category: category) }

  def to_param
    slug
  end

  def published?
    published && published_at.present?
  end

  def category_display_name
    case category
    when 'release' then 'Release Notes'
    when 'feature' then 'Feature Announcements'
    when 'tutorial' then 'Tutorials'
    when 'announcement' then 'Announcements'
    when 'business-tips' then 'Business Tips'
    when 'spotlight' then 'Customer Spotlights'
    when 'platform-updates' then 'Platform Updates'
    else category&.humanize
    end
  end

  def url_path
    return unless published_at && slug
    
    date = published_at.to_date
    "/blog/#{date.year}/#{date.month.to_s.rjust(2, '0')}/#{date.day.to_s.rjust(2, '0')}/#{slug}/"
  end

  def rendered_content
    MarkdownRenderer.render(content)
  end

  def rendered_excerpt
    MarkdownRenderer.render(excerpt)
  end

  # Returns attachment object if present, otherwise nil
  def featured_image_for_display
    featured_image.attached? ? featured_image : nil
  end

  # Returns URL string for fallback
  def featured_image_fallback_url
    featured_image_url.present? ? featured_image_url : nil
  end

  private

  def generate_slug
    base_slug = title.parameterize
    slug_candidate = base_slug
    counter = 1

    while BlogPost.exists?(slug: slug_candidate)
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = slug_candidate
  end

  def set_published_at
    self.published_at = Time.current if published_at.blank?
  end

  def handle_featured_image_removal
    if remove_featured_image == '1' || remove_featured_image == true
      featured_image.purge if featured_image.attached?
    end
  end

  def send_publication_notifications
    # Send email notifications to subscribed users
    BlogNotificationJob.perform_later(id)
  end
end 