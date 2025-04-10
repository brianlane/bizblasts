class ServiceTemplate < ApplicationRecord
  has_many :businesses, foreign_key: :service_template_id, dependent: :nullify

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
  scope :published, -> { where.not(published_at: nil) }
  scope :by_industry, ->(industry) { where(industry: industry) }

  # Define which attributes are searchable by Ransack/ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description industry active published_at template_type created_at updated_at]
    # Include enums, exclude structure
  end

  # Define searchable associations
  def self.ransackable_associations(auth_object = nil)
    %w[businesses]
  end

  # Placeholder for template application logic
  def apply_to_business(business)
    return false unless active? && published_at.present?

    # Associate the template with the business
    business.update(service_template_id: id)

    # Create pages and sections based on template structure
    structure['pages']&.each do |page_data|
      page = business.pages.create!(
        title: page_data['title'],
        slug: page_data['slug'],
        page_type: page_data['page_type'],
        content: page_data['content']
      )
      
      page_data['sections']&.each do |section_data|
        page.page_sections.create!(
          section_type: section_data['section_type'],
          content: section_data['content'],
          position: section_data['position']
        )
      end
    end
    
    # Apply template settings if present
    if structure['settings'].present?
      business.update(
        theme: structure['settings']['theme'],
        settings: business.settings.merge(structure['settings'])
      )
    end

    true # Return true on success
  rescue => e
    Rails.logger.error("Error applying template #{id} to business #{business.id}: #{e.message}")
    false # Return false on failure
  end

  def published?
    published_at.present?
  end
end 