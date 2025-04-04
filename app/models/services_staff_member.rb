class ServicesStaffMember < ApplicationRecord
  include TenantScoped
  
  belongs_to :service
  belongs_to :staff_member
  
  validates :service_id, uniqueness: { scope: [:business_id, :staff_member_id] }
end 