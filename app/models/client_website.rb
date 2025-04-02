class ClientWebsite < ApplicationRecord
  belongs_to :company
  belongs_to :service_template

  validates :name, presence: true
  validates :subdomain, uniqueness: { scope: :company_id }, allow_blank: true
  validates :domain, uniqueness: true, allow_blank: true

  acts_as_tenant(:company)
end 