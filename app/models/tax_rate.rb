# app/models/tax_rate.rb
class TaxRate < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  has_many :orders
  has_many :invoices # Assuming invoices might also use tax rates

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 } # Rate as decimal (e.g., 0.08 for 8%)
  # validates :region, presence: true # Add validation if region is used for selection
  # validates :applies_to_shipping, inclusion: { in: [true, false] } # Should be explicit

  def calculate_tax(amount)
    (amount * rate).round(2)
  end

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    %w[id name rate region applies_to_shipping active business_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business orders invoices]
  end
  # --- End Ransack methods ---
end 