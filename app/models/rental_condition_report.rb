# frozen_string_literal: true

class RentalConditionReport < ApplicationRecord
  belongs_to :rental_booking
  belongs_to :staff_member, optional: true

  # Delegate business for tenant scoping
  delegate :business, :business_id, to: :rental_booking

  # Photo attachments for condition documentation
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_fill: [200, 200]
    attachable.variant :medium, resize_to_fill: [800, 600]
    attachable.variant :large, resize_to_limit: [1600, 1200]
  end

  # Report types
  REPORT_TYPES = %w[checkout return].freeze

  # Condition ratings
  CONDITION_RATINGS = %w[excellent good fair poor damaged].freeze

  # Maximum number of photos per report
  MAX_PHOTOS = 10

  validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
  validates :condition_rating, inclusion: { in: CONDITION_RATINGS }, allow_nil: true
  validates :damage_assessment_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Validate photo attachments using FileUploadSecurity
  validates :photos, **FileUploadSecurity.image_validation_options
  validate :photo_count_limit
  validate :photo_size_validation
  validate :photo_format_validation
  
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

  # Check if report has photos attached
  def has_photos?
    photos.attached?
  end

  # Get count of attached photos
  def photo_count
    photos.count
  end

  private

  def photo_count_limit
    if photos.count > MAX_PHOTOS
      errors.add(:photos, "cannot exceed #{MAX_PHOTOS} photos per report")
    end
  end

  def photo_size_validation
    photos.each do |photo|
      if photo.blob.byte_size > 15.megabytes
        errors.add(:photos, "must be less than 15MB each")
      end
    end
  end

  def photo_format_validation
    photos.each do |photo|
      unless FileUploadSecurity.valid_image_type?(photo.blob.content_type)
        errors.add(:photos, FileUploadSecurity.image_validation_options[:content_type][:message])
        break
      end
    end
  end
end

