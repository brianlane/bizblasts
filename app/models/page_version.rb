class PageVersion < ApplicationRecord
  belongs_to :page
  belongs_to :created_by, class_name: 'User', optional: true
  
  validates :version_number, presence: true, uniqueness: { scope: :page_id }
  validates :content_snapshot, presence: true
  
  enum :status, { draft: 0, published: 1, archived: 2 }
  
  scope :latest, -> { order(version_number: :desc) }
  scope :published_versions, -> { where(status: :published) }
  
  before_validation :set_version_number, on: :create
  
  def self.create_from_page(page, user = nil, notes = nil)
    create!(
      page: page,
      created_by: user,
      content_snapshot: capture_page_snapshot(page),
      change_notes: notes,
      status: page.published? ? :published : :draft
    )
  end
  
  def restore_to_page!
    return false unless content_snapshot.present?
    
    page.transaction do
      # Restore page attributes
      if content_snapshot['page_attributes']
        page.update!(content_snapshot['page_attributes'].except('id', 'created_at', 'updated_at'))
      end
      
      # Restore sections
      if content_snapshot['sections']
        page.page_sections.destroy_all
        content_snapshot['sections'].each do |section_data|
          page.page_sections.create!(section_data.except('id', 'created_at', 'updated_at'))
        end
      end
      
      # Create new version for the restoration
      PageVersion.create_from_page(page, created_by, "Restored from version #{version_number}")
    end
    
    true
  end
  
  def publish!
    return false if published?
    
    page.transaction do
      # Unpublish other versions
      page.page_versions.published_versions.update_all(status: :archived)
      
      # Publish this version
      update!(status: :published, published_at: Time.current)
      
      # Apply this version to the page
      restore_to_page!
      
      # Update page status
      page.update!(status: :published, published_at: Time.current)
    end
    
    true
  end
  
  private
  
  def set_version_number
    self.version_number = (page.page_versions.maximum(:version_number) || 0) + 1
  end
  
  def self.capture_page_snapshot(page)
    {
      page_attributes: page.attributes,
      sections: page.page_sections.ordered.map(&:attributes),
      theme_settings: page.business.active_website_theme&.attributes,
      timestamp: Time.current
    }
  end
end 