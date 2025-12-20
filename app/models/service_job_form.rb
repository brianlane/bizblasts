# frozen_string_literal: true

class ServiceJobForm < ApplicationRecord
  belongs_to :service
  belongs_to :job_form_template

  # Timing enum - when should this form be completed
  enum :timing, {
    before_service: 0,
    during_service: 1,
    after_service: 2
  }

  # Validations
  validates :service, presence: true
  validates :job_form_template, presence: true
  validates :timing, presence: true
  validates :job_form_template_id, uniqueness: { scope: :service_id, message: 'is already assigned to this service' }

  # Ensure the form template belongs to the same business as the service
  validate :same_business_validation

  # Scopes
  scope :required_forms, -> { where(required: true) }
  scope :optional_forms, -> { where(required: false) }
  scope :before_forms, -> { where(timing: :before_service) }
  scope :during_forms, -> { where(timing: :during_service) }
  scope :after_forms, -> { where(timing: :after_service) }

  # Delegate business to service for tenant scoping
  delegate :business, to: :service, allow_nil: true
  delegate :business_id, to: :service, allow_nil: true

  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id service_id job_form_template_id required timing created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[service job_form_template]
  end

  # Display name for the association
  def display_name
    "#{job_form_template&.name} (#{timing_display})"
  end

  # Human-readable timing display
  def timing_display
    case timing
    when 'before_service' then 'Before'
    when 'during_service' then 'During'
    when 'after_service' then 'After'
    else timing&.humanize
    end
  end

  private

  def same_business_validation
    return unless service.present? && job_form_template.present?

    if service.business_id != job_form_template.business_id
      errors.add(:job_form_template, 'must belong to the same business as the service')
    end
  end
end
