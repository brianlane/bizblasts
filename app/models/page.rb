class Page < ApplicationRecord
  include TenantScoped
  
  has_many :page_sections, dependent: :destroy
  
  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :business_id }
  validates :meta_description, length: { maximum: 160 }, allow_blank: true
  
  enum :page_type, {
    home: 0,
    about: 1,
    services: 2,
    contact: 3,
    custom: 4
  }
  
  scope :published, -> { where(published: true) }
  scope :menu_items, -> { where(show_in_menu: true).order(:menu_order) }
  
  def to_param
    slug
  end
  
  def publish!
    self.published = true
    self.published_at = Time.current
    save
  end
end
