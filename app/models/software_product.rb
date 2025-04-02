class SoftwareProduct < ApplicationRecord
  has_many :software_subscriptions, dependent: :restrict_with_error
  
  validates :name, presence: true
  
  scope :active, -> { where(active: true) }
  scope :published, -> { where(status: 'published') }
end 