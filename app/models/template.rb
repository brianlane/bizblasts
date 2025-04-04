class Template < ApplicationRecord
  include TenantScoped
  
  has_many :pages, dependent: :destroy
  has_many :businesses
  
  validates :name, presence: true
  validates :industry, presence: true
  validates :template_type, presence: true
  
  enum :industry, {
    landscaping: 0,
    pool_service: 1,
    home_service: 2,
    general: 3
  }
  
  enum :template_type, {
    booking: 0,
    marketing: 1,
    full_website: 2
  }
  
  scope :active, -> { where(active: true) }
  scope :by_industry, ->(industry) { where(industry: industry) }
  
  def apply_to_business(business)
    # Logic to apply template to a business
    # This would create pages, services, etc. based on the template
    return false unless active?
    
    # Placeholder implementation
    business.update(template_id: id)
    true
  end
end
