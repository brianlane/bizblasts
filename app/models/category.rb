# app/models/category.rb
class Category < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  has_many :products

  validates :name, presence: true, uniqueness: { scope: :business_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position) }

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    %w[id name description position active business_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business products]
  end
  # --- End Ransack methods ---
end 