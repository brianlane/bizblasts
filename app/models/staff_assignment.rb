class StaffAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :service

  # Allowlist attributes for Ransack searching (used by ActiveAdmin)
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "service_id", "updated_at", "user_id"]
  end

  # Allowlist associations for Ransack searching (optional, add if needed)
  # def self.ransackable_associations(auth_object = nil)
  #   ["service", "user"]
  # end
end
