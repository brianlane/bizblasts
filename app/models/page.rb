class Page < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  has_many :page_sections, dependent: :destroy
  has_many :page_versions, dependent: :destroy
  has_rich_text :content  # Add ActionText support
  
  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :business_id }
  validates :meta_description, length: { maximum: 160 }, allow_blank: true
  validate :customization_allowed_for_tier
  
  enum :page_type, {
    home: 0,
    about: 1,
    services: 2,
    contact: 3,
    custom: 4,
    portfolio: 5,
    team: 6,
    pricing: 7
  }
  
  enum :status, { draft: 0, published: 1, archived: 2 }
  
  scope :published, -> { where(status: :published) }
  scope :menu_items, -> { where(show_in_menu: true).order(:menu_order) }
  scope :customizable, -> { joins(:business).where(businesses: { tier: ['standard', 'premium'] }) }
  scope :by_priority, -> { order(priority: :desc, updated_at: :desc) }
  scope :popular, -> { where('view_count > 0').order(view_count: :desc) }
  scope :recent, -> { order(updated_at: :desc) }
  
  before_validation :generate_slug, if: -> { slug.blank? && title.present? }
  
  def to_param
    id.to_s
  end
  
  def to_slug_param
    slug
  end
  
  def publish!
    transaction do
      update!(status: :published, published_at: Time.current)
      PageVersion.create_from_page(self)
    end
  end
  
  def create_draft_version!(user = nil, notes = nil)
    PageVersion.create_from_page(self, user, notes)
  end
  
  def latest_version
    page_versions.latest.first
  end
  
  def can_be_customized?
    business&.standard_tier? || business&.premium_tier?
  end
  
  def has_custom_sections?
    page_sections.where.not(section_type: ['text', 'header', 'contact_form']).exists?
  end
  
  
  def increment_view_count!
    increment!(:view_count)
    touch(:last_viewed_at)
  end
  
  def priority_level
    case priority
    when 0 then 'normal'
    when 1..3 then 'medium'
    when 4..6 then 'high'
    else 'critical'
    end
  end
  
  def status_color
    case status
    when 'published' then 'green'
    when 'draft' then 'yellow'
    when 'archived' then 'gray'
    else 'gray'
    end
  end
  
  def performance_rating
    return 'unknown' if performance_score.nil?
    case performance_score
    when 0..30 then 'poor'
    when 31..60 then 'fair'
    when 61..80 then 'good'
    when 81..100 then 'excellent'
    else 'unknown'
    end
  end
  
  private
  
  def customization_allowed_for_tier
    return if business.nil?

    if business.free_tier?
      return if business.website_layout_enhanced?
      return unless has_custom_sections?

      errors.add(:base, "Advanced website customization requires Standard or Premium tier")
      return
    end

    unless business.standard_tier? || business.premium_tier?
      errors.add(:base, "Advanced website customization requires Standard or Premium tier")
    end
  end
  
  # Auto-generate a unique slug from the title if none provided.
  # Mirrors the behaviour used by BlogPost so website pages can be
  # created via the UI without manually entering a slug.
  def generate_slug
    base_slug = title.to_s.parameterize
    candidate = base_slug
    counter   = 1

    # Scope uniqueness to the current business just like the validation.
    while self.class.where(business_id: business_id).exists?(slug: candidate)
      candidate = "#{base_slug}-#{counter}"
      counter  += 1
    end

    self.slug = candidate
  end
end
