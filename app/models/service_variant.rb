# frozen_string_literal: true

class ServiceVariant < ApplicationRecord
  belongs_to :service
  has_many :bookings, dependent: :nullify # bookings keep reference even if variant removed

  delegate :business, to: :service, allow_nil: true

  # Scopes
  default_scope { order(:position, :created_at) }
  scope :by_position, -> { order(:position, :created_at) }

  # Validations
  validates :name, presence: true
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Callbacks
  before_create :set_position_to_end, unless: :position?

  def label
    "#{name} (#{duration} min)"
  end

  # Promotional pricing delegated to service's promotion logic
  def promotional_price
    return price unless service.on_promotion?
    service.current_promotion.calculate_promotional_price(price)
  end

  private

  def set_position_to_end
    max_position = service&.service_variants&.maximum(:position) || -1
    self.position = max_position + 1
  end

  # --- ActiveAdmin / Ransack ---
  def self.ransackable_attributes(auth_object = nil)
    %w[id service_id name duration price active position created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[service bookings]
  end
end 