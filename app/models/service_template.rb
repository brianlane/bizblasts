class ServiceTemplate < ApplicationRecord
  has_many :client_websites, dependent: :restrict_with_error

  validates :name, presence: true
  
  scope :active, -> { where(active: true) }
end 