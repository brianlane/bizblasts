# app/models/shipping_method.rb
class ShippingMethod < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  has_many :orders
  has_many :invoices # Assuming invoices might also use shipping methods

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    %w[id name cost active business_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business orders invoices]
  end
  # --- End Ransack methods ---
end 