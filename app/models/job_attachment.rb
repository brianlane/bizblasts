# frozen_string_literal: true

class JobAttachment < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :attachable, polymorphic: true
  belongs_to :uploaded_by_user, class_name: 'User', optional: true

  # File attachment with variants for images
  has_one_attached :file do |attachable|
    attachable.variant :thumb, resize_to_fill: [200, 200]
    attachable.variant :medium, resize_to_limit: [800, 800]
    attachable.variant :large, resize_to_limit: [1600, 1600]
  end

  # Attachment type enum
  enum :attachment_type, {
    before_photo: 0,
    after_photo: 1,
    instruction: 2,
    reference_file: 3,
    general: 4
  }

  # Visibility enum (who can see this attachment)
  enum :visibility, {
    internal: 0,          # Only staff/business can see
    customer_visible: 1   # Customer can also see
  }, prefix: true

  # Validations
  validates :business, presence: true
  validates :attachable, presence: true
  validates :attachment_type, presence: true
  validates :visibility, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :title, length: { maximum: 255 }, allow_blank: true
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validates :instructions, length: { maximum: 5000 }, allow_blank: true

  # Validate file type and size
  validate :validate_file_type
  validate :validate_file_size

  # Scopes
  scope :ordered, -> { order(:position, :created_at) }
  scope :photos, -> { where(attachment_type: [:before_photo, :after_photo]) }
  scope :before_photos, -> { where(attachment_type: :before_photo) }
  scope :after_photos, -> { where(attachment_type: :after_photo) }
  scope :instructions, -> { where(attachment_type: :instruction) }
  scope :files, -> { where(attachment_type: [:reference_file, :general]) }
  scope :visible_to_customer, -> { where(visibility: :customer_visible) }
  scope :internal_only, -> { where(visibility: :internal) }

  # Callbacks
  before_create :set_position_to_end, unless: :position?
  after_commit :process_image, on: [:create, :update], if: :image?

  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id attachable_type attachable_id attachment_type title visibility position created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business attachable uploaded_by_user file_attachment file_blob]
  end

  # Check if the attachment is an image
  def image?
    return false unless file.attached?
    file.content_type.start_with?('image/')
  end

  # Check if the attachment is a PDF
  def pdf?
    return false unless file.attached?
    file.content_type == 'application/pdf'
  end

  # Get a display name for the attachment
  def display_name
    title.presence || file.filename.to_s
  end

  # Get file size in human readable format
  def file_size_display
    return nil unless file.attached?
    ActionController::Base.helpers.number_to_human_size(file.byte_size)
  end

  private

  def set_position_to_end
    max_position = attachable&.job_attachments&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def validate_file_type
    return unless file.attached?

    allowed_types = %w[
      image/jpeg image/png image/gif image/webp image/heic image/heif
      application/pdf
      application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      text/plain text/csv
    ]

    unless allowed_types.include?(file.content_type)
      errors.add(:file, 'must be an image, PDF, document, or spreadsheet')
    end
  end

  def validate_file_size
    return unless file.attached?

    max_size = image? ? 15.megabytes : 25.megabytes

    if file.byte_size > max_size
      max_display = ActionController::Base.helpers.number_to_human_size(max_size)
      errors.add(:file, "must be less than #{max_display}")
    end
  end

  def process_image
    return unless file.attached? && image?
    ProcessImageJob.perform_later(file.id)
  end
end
