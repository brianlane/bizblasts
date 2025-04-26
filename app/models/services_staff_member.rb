class ServicesStaffMember < ApplicationRecord
  # Remove TenantScoped - tenancy enforced by Service and StaffMember
  # include TenantScoped 
  
  belongs_to :service
  belongs_to :staff_member
  
  # Remove business_id from scope - it doesn't exist on this table
  validates :service_id, uniqueness: { scope: :staff_member_id }

  # Define ransackable attributes for ActiveAdmin/Ransack
  def self.ransackable_attributes(auth_object = nil)
    # Allow searching/filtering by the foreign keys and timestamps
    ["created_at", "id", "service_id", "staff_member_id", "updated_at"]
  end

  # Define ransackable associations (likely none needed for a simple join model)
  def self.ransackable_associations(auth_object = nil)
    [] # Typically, join models don't need further associations exposed
  end
end 