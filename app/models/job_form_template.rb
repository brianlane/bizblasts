# frozen_string_literal: true

class JobFormTemplate < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)
  belongs_to :business

  has_many :service_job_forms, dependent: :destroy
  has_many :services, through: :service_job_forms
  has_many :job_form_submissions, dependent: :restrict_with_error

  # Form type enum
  enum :form_type, {
    checklist: 0,
    inspection: 1,
    completion_report: 2,
    custom: 3
  }

  # Validations
  validates :business, presence: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :business_id, case_sensitive: false }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validates :form_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :validate_fields_structure

  # Scopes
  scope :ordered, -> { order(:position, :name) }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # Callbacks
  before_validation :set_position_to_end, on: :create, if: -> { position.nil? }
  before_save :normalize_fields

  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id name description form_type active position created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business service_job_forms services job_form_submissions]
  end

  # Get fields as structured array
  def form_fields
    (fields.is_a?(Hash) ? fields['fields'] : []) || []
  end

  # Set fields from structured array
  def form_fields=(field_array)
    self.fields = { 'fields' => field_array }
  end

  # Virtual attribute for JSON form fields (used by the form builder)
  attr_accessor :form_fields_json

  # Override form_fields_json= to also set form_fields
  def form_fields_json=(json_string)
    @form_fields_json = json_string
    if json_string.present?
      parsed = json_string.is_a?(String) ? JSON.parse(json_string) : json_string
      self.form_fields = parsed
    end
  rescue JSON::ParserError
    @form_fields_json = json_string
  end

  # Add a new field to the form
  def add_field(field_attrs)
    current_fields = form_fields
    new_field = {
      'id' => SecureRandom.uuid,
      'type' => field_attrs[:type] || 'text',
      'label' => field_attrs[:label],
      'required' => field_attrs[:required] || false,
      'options' => field_attrs[:options] || [],
      'default_value' => field_attrs[:default_value],
      'position' => current_fields.length,
      'placeholder' => field_attrs[:placeholder],
      'help_text' => field_attrs[:help_text]
    }.compact

    self.form_fields = current_fields + [new_field]
  end

  # Remove a field by ID
  def remove_field(field_id)
    self.form_fields = form_fields.reject { |f| f['id'] == field_id }
    resequence_field_positions
  end

  # Reorder fields
  def reorder_fields(field_ids)
    current = form_fields.index_by { |f| f['id'] }
    reordered = field_ids.filter_map { |id| current[id] }
    reordered.each_with_index { |f, i| f['position'] = i }
    self.form_fields = reordered
  end

  # Get count of required fields
  def required_field_count
    form_fields.count { |f| f['required'] }
  end

  # Check if form has any photo fields
  def has_photo_fields?
    form_fields.any? { |f| f['type'] == 'photo' }
  end

  # Duplicate this template
  def duplicate(new_name: nil)
    dup.tap do |copy|
      copy.name = new_name || "#{name} (Copy)"
      copy.position = nil # Will be set by callback
      copy.fields = fields.deep_dup
    end
  end

  # Supported field types
  FIELD_TYPES = %w[
    checkbox
    text
    textarea
    photo
    select
    number
    date
    time
    signature
  ].freeze

  private

  def set_position_to_end
    max_position = business&.job_form_templates&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def normalize_fields
    self.fields ||= { 'fields' => [] }
    self.fields = { 'fields' => [] } unless fields.is_a?(Hash)
    self.fields['fields'] ||= []
    self.fields['fields'] = Array(self.fields['fields'])
  end

  def resequence_field_positions
    form_fields.each_with_index { |f, i| f['position'] = i }
  end

  def validate_fields_structure
    return unless fields.present?

    unless fields.is_a?(Hash) && fields['fields'].is_a?(Array)
      errors.add(:fields, 'must have a valid structure')
      return
    end

    fields['fields'].each_with_index do |field, index|
      unless field.is_a?(Hash)
        errors.add(:fields, "field at position #{index} is invalid")
        next
      end

      unless field['id'].present? && field['type'].present? && field['label'].present?
        errors.add(:fields, "field at position #{index} is missing required attributes (id, type, label)")
      end

      unless FIELD_TYPES.include?(field['type'])
        errors.add(:fields, "field '#{field['label']}' has invalid type '#{field['type']}'")
      end

      if field['type'] == 'select' && !field['options'].is_a?(Array)
        errors.add(:fields, "field '#{field['label']}' of type 'select' must have options array")
      end
    end
  end
end
