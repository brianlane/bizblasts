# frozen_string_literal: true

class ServiceVariant < ApplicationRecord
  belongs_to :service
  has_many :bookings, dependent: :nullify # bookings keep reference even if variant removed

  delegate :business, to: :service, allow_nil: true

  # Scopes
  default_scope { order(:position, :created_at) }
  scope :by_position, -> { order(:position, :created_at) }
  scope :active, -> { where(active: true) }

  # Validations
  validates :name, presence: true,
                   uniqueness: { scope: [:service_id, :duration], case_sensitive: false,
                                message: "must be unique for each duration within a service" }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # Custom setters to parse numbers from strings with non-numeric characters
  def duration=(value)
    if value.is_a?(String)
      # Extract only digits from the string (e.g., "60 min" -> "60")
      parsed_value = value.gsub(/[^\d]/, '').to_i
      super(parsed_value > 0 ? parsed_value : nil)
    else
      super(value)
    end
  end
  
  def price=(value)
    if value.is_a?(String) && value.present?
      # Extract valid decimal number (positive only for prices)
      # Matches patterns like: "60.50", "$60.50", "$60", "60"
      match = value.match(/(\d+(?:\.\d+)?)/)
      if match
        parsed_float = match[1].to_f.round(2)
        super(parsed_float >= 0 ? parsed_float : 0.0)
      else
        # Add helpful validation error for invalid input format
        errors.add(:price, "must be a valid number (e.g., '10.50' or '$10.50')")
        return
      end
    elsif value.nil? || (value.is_a?(String) && value.blank?)
      # Don't set nil for blank/empty strings
      return
    else
      super(value)
    end
  end
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