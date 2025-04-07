class ServiceTemplate < ApplicationRecord
  # Removed has_many :client_websites association

  validates :name, presence: true
  
  scope :active, -> { where(active: true) }

  # Define which attributes are searchable by Ransack/ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    # List all attributes from the migration, plus id, created_at, updated_at
    %w[id name description category industry active status features pricing content settings published_at metadata created_at updated_at]
  end

  # Optionally define searchable associations if needed
  # def self.ransackable_associations(auth_object = nil)
  #   [] # Add association names here, e.g., %w[client_websites]
  # end
end 