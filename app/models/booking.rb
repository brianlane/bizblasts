# frozen_string_literal: true

class Booking < ApplicationRecord
  include TenantScoped
  include BookingStatus
  include BookingScopes
  include BookingValidations
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :service
  belongs_to :staff_member
  belongs_to :tenant_customer
  accepts_nested_attributes_for :tenant_customer
  belongs_to :promotion, optional: true
  has_one :invoice, dependent: :nullify
  has_many :booking_product_add_ons, dependent: :destroy
  has_many :add_on_product_variants, through: :booking_product_add_ons, source: :product_variant
  accepts_nested_attributes_for :booking_product_add_ons, allow_destroy: true,
                                reject_if: proc { |attributes| attributes['quantity'].to_i <= 0 || attributes['product_variant_id'].blank? }
  
  delegate :name, to: :service, prefix: true, allow_nil: true
  delegate :name, to: :staff_member, prefix: true, allow_nil: true
  delegate :name, :email, to: :tenant_customer, prefix: :customer, allow_nil: true
  
  def total_charge
    service_cost = self.service&.price || 0
    addons_cost = self.booking_product_add_ons.sum(&:total_amount)
    service_cost + addons_cost
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id start_time end_time status notes service_id staff_member_id tenant_customer_id 
       business_id created_at updated_at amount original_amount discount_amount cancellation_reason]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business service staff_member tenant_customer invoice promotion]
  end
end
