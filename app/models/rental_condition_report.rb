# frozen_string_literal: true

class RentalConditionReport < ApplicationRecord
  belongs_to :rental_booking
  belongs_to :staff_member, optional: true
  
  # Delegate business for tenant scoping
  delegate :business, :business_id, to: :rental_booking
  
  # Report types
  REPORT_TYPES = %w[checkout return].freeze
  
  # Condition ratings
  CONDITION_RATINGS = %w[excellent good fair poor damaged].freeze
  
  validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
  validates :condition_rating, inclusion: { in: CONDITION_RATINGS }, allow_nil: true
  validates :damage_assessment_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  scope :checkout_reports, -> { where(report_type: 'checkout') }
  scope :return_reports, -> { where(report_type: 'return') }
  
  # Check if this is a checkout report
  def checkout?
    report_type == 'checkout'
  end
  
  # Check if this is a return report
  def return?
    report_type == 'return'
  end
  
  # Check if damage was assessed
  def has_damage?
    damage_assessment_amount.to_d > 0
  end
  
  # Get condition rating display
  def condition_display
    condition_rating&.titleize || 'Not rated'
  end
  
  # Get checklist summary
  def checklist_summary
    return [] unless checklist_items.is_a?(Array)
    
    checklist_items.map do |item|
      {
        item: item['item'] || item[:item],
        condition: item['condition'] || item[:condition],
        notes: item['notes'] || item[:notes]
      }
    end
  end
  
  # Staff member name display
  def staff_name
    staff_member&.name || 'Unknown'
  end
end

