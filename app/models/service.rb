# frozen_string_literal: true

class Service < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :bookings, dependent: :restrict_with_error
  has_and_belongs_to_many :staff_members
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  
  scope :active, -> { where(active: true) }
  
  def self.available_for_booking(staff_member_id = nil)
    scope = active
    scope = scope.joins(:staff_members).where(staff_members: { id: staff_member_id }) if staff_member_id.present?
    scope
  end
  
  def assigned_staff_members
    staff_members
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description duration price active business_id created_at updated_at]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings staff_members]
  end
end 