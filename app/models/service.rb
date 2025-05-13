# frozen_string_literal: true

class Service < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :staff_assignments, source: :user
  has_many :services_staff_members, dependent: :destroy
  has_many :staff_members, through: :services_staff_members
  has_many :bookings, dependent: :restrict_with_error
  
  # Add-on products association
  has_many :product_service_add_ons, dependent: :destroy
  has_many :add_on_products, through: :product_service_add_ons, source: :product
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :business_id, presence: true
  
  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  
  # Optional: Define an enum for duration if you have standard lengths
  # enum duration_minutes: { thirty_minutes: 30, sixty_minutes: 60, ninety_minutes: 90 }
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description duration price active business_id created_at updated_at featured]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings staff_assignments assigned_staff services_staff_members staff_members product_service_add_ons add_on_products]
  end

  def available_add_on_products
    # Only include service and mixed products as add-ons
    add_on_products.active.where(product_type: [:service, :mixed])
                       .includes(:product_variants) # Eager load variants for the form
                       .where.not(product_variants: { id: nil }) # Ensure they have variants
  end
end 