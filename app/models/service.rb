# frozen_string_literal: true

class Service < ApplicationRecord
  belongs_to :company
  has_many :appointments, dependent: :restrict_with_error # Prevent deleting service if appointments exist

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # duration_minutes is the field name from the migration
  validates :duration_minutes, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :active, inclusion: { in: [true, false] }
end 