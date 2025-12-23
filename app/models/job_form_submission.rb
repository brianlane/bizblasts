# frozen_string_literal: true

class JobFormSubmission < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :booking
  belongs_to :job_form_template
  belongs_to :staff_member, optional: true
  belongs_to :submitted_by_user, class_name: 'User', optional: true
  belongs_to :approved_by_user, class_name: 'User', optional: true

  # Photo attachments for photo-type fields
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_fill: [200, 200]
    attachable.variant :medium, resize_to_limit: [800, 800]
    attachable.variant :large, resize_to_limit: [1600, 1600]
  end

  # File attachments for general uploads
  has_many_attached :files

  # Server-side file upload validation
  validates :photos, **FileUploadSecurity.image_validation_options
  validates :files, size: { less_than: FileUploadSecurity::MAX_IMAGE_SIZE, message: 'must be less than 15MB' }
  validate :photos_count_validation
  validate :files_count_validation

  # Status enum
  enum :status, {
    draft: 0,
    submitted: 1,
    approved: 2,
    requires_revision: 3
  }

  # Validations
  validates :business, presence: true
  validates :booking, presence: true
  validates :job_form_template, presence: true
  validates :status, presence: true
  validates :job_form_template_id, uniqueness: { scope: :booking_id,
                                                   message: 'submission already exists for this booking' }
  validate :same_business_validation
  validate :validate_required_fields

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :pending_review, -> { where(status: :submitted) }
  scope :completed, -> { where(status: [:approved, :requires_revision]) }
  scope :for_booking, ->(booking_id) { where(booking_id: booking_id) }
  scope :for_template, ->(template_id) { where(job_form_template_id: template_id) }

  # Callbacks
  before_save :set_submitted_at, if: :will_be_submitted?
  before_save :set_approved_at, if: :will_be_approved?

  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id booking_id job_form_template_id staff_member_id status submitted_at approved_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business booking job_form_template staff_member submitted_by_user approved_by_user photos_attachments files_attachments]
  end

  # Get response for a specific field
  # Uses safe navigation to handle nil responses (can happen for existing submissions loaded from DB)
  def response_for(field_id)
    responses&.[](field_id.to_s)
  end

  # Set response for a specific field
  def set_response(field_id, value)
    self.responses ||= {}
    self.responses[field_id.to_s] = value
  end

  # Get all responses with field labels
  def responses_with_labels
    template_fields = job_form_template&.form_fields || []
    template_fields.map do |field|
      {
        field_id: field['id'],
        label: field['label'],
        type: field['type'],
        required: field['required'],
        value: response_for(field['id'])
      }
    end
  end

  # Check if all required fields are filled
  def all_required_fields_filled?
    template_fields = job_form_template&.form_fields || []
    required_fields = template_fields.select { |f| f['required'] }

    required_fields.all? do |field|
      value = response_for(field['id'])
      field_value_present?(value, field['type'])
    end
  end

  # Check if a field value is considered "present" based on field type
  # Handles checkbox fields specially since "false" string should not count as filled.
  # For required checkbox fields, this means the checkbox MUST be checked (true) to pass validation.
  # This is the intended behavior - an unchecked required checkbox will fail validation.
  def field_value_present?(value, field_type)
    return false if value.blank?

    # For checkbox fields, only a checked (true) checkbox counts as "present"
    # The string "false" means unchecked and will not satisfy required field validation
    if field_type == 'checkbox'
      return ActiveModel::Type::Boolean.new.cast(value) == true
    end

    true
  end

  # Calculate completion percentage
  def completion_percentage
    template_fields = job_form_template&.form_fields || []
    return 100 if template_fields.empty?

    filled_count = template_fields.count { |f| field_value_present?(response_for(f['id']), f['type']) }
    ((filled_count.to_f / template_fields.length) * 100).round
  end

  # Submit the form
  def submit!(user: nil)
    unless all_required_fields_filled?
      # Add validation errors for missing required fields
      add_required_field_errors
      return false
    end

    self.submitted_by_user = user if user
    self.status = :submitted
    save
  end

  # Add validation errors for missing required fields
  def add_required_field_errors
    template_fields = job_form_template&.form_fields || []
    required_fields = template_fields.select { |f| f['required'] }

    required_fields.each do |field|
      value = response_for(field['id'])
      unless field_value_present?(value, field['type'])
        errors.add(:base, "#{field['label']} is required")
      end
    end
  end

  # Approve the form
  def approve!(user:)
    return false unless submitted?

    self.approved_by_user = user
    self.status = :approved
    save
  end

  # Request revision
  def request_revision!(user:, notes: nil)
    return false unless submitted?

    self.approved_by_user = user
    self.notes = notes if notes.present?
    self.status = :requires_revision
    save
  end

  # Check if this submission is editable
  def editable?
    draft? || requires_revision?
  end

  # Get display name
  def display_name
    "#{job_form_template&.name} - #{booking&.service_name} (#{status.humanize})"
  end

  private

  def same_business_validation
    return unless booking.present? && job_form_template.present?

    if booking.business_id != job_form_template.business_id
      errors.add(:job_form_template, 'must belong to the same business as the booking')
    end

    if business_id != booking.business_id
      errors.add(:business, 'must match the booking business')
    end
  end

  def validate_required_fields
    # Only validate required fields when transitioning to submitted status
    return unless status == 'submitted' && status_changed?
    return if all_required_fields_filled?

    template_fields = job_form_template&.form_fields || []
    required_fields = template_fields.select { |f| f['required'] }

    required_fields.each do |field|
      value = response_for(field['id'])
      unless field_value_present?(value, field['type'])
        errors.add(:base, "#{field['label']} is required")
      end
    end
  end

  def will_be_submitted?
    status_changed? && submitted?
  end

  def will_be_approved?
    status_changed? && approved?
  end

  def set_submitted_at
    self.submitted_at ||= Time.current
  end

  def set_approved_at
    self.approved_at = Time.current
  end

  # Validate photo attachment count (max 10 files)
  def photos_count_validation
    return unless photos.attached?

    if photos.count > 10
      errors.add(:photos, 'cannot exceed 10 files')
    end
  end

  # Validate file attachment count (max 10 files)
  def files_count_validation
    return unless files.attached?

    if files.count > 10
      errors.add(:files, 'cannot exceed 10 files')
    end
  end
end
