class SoftwareSubscription < ApplicationRecord
  belongs_to :company
  belongs_to :software_product
  
  validates :license_key, uniqueness: true, allow_blank: true
  
  acts_as_tenant(:company)
  
  scope :active, -> { where(status: 'active') }
end 