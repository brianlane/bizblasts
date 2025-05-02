# app/models/product.rb
class Product < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  belongs_to :category, optional: true
  has_many :product_variants, dependent: :destroy
  # If variants are mandatory, line_items might associate through variants
  # has_many :line_items, dependent: :destroy # Use this if products DON'T have variants
  has_many :line_items, through: :product_variants # Use this if products MUST have variants

  has_many_attached :images

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # Validate attachments using built-in ActiveStorage validators
  validates :images, content_type: ['image/png', 'image/jpeg'], size: { less_than: 5.megabytes }

  # TODO: Add method or validation for primary image designation if needed
  # TODO: Add method for image ordering if needed

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }

  # Allows creating variants directly when creating/updating a product
  accepts_nested_attributes_for :product_variants, allow_destroy: true

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    # Include basic fields, foreign keys, flags, and timestamps
    %w[id name description price active featured category_id business_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business category product_variants line_items images_attachments images_blobs]
  end
  # --- End Ransack methods ---

  # Delegate stock check to variants if they exist, otherwise maybe self (if stock on product)
  # def in_stock?(requested_quantity = 1)
  #   # Logic depends on whether variants are mandatory
  # end

  # If products can be sold without variants, add stock logic here
  # validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, unless: :has_variants?
  # def has_variants?
  #  product_variants.exists?
  # end
end 