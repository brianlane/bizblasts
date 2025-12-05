# frozen_string_literal: true

class ClientDocument < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft sent pending_signature pending_payment completed void].freeze

  belongs_to :business
  belongs_to :tenant_customer, optional: true
  belongs_to :documentable, polymorphic: true, optional: true
  belongs_to :invoice, optional: true
  belongs_to :document_template, optional: true

  has_many :document_signatures, dependent: :destroy
  has_many :client_document_events, dependent: :destroy

  has_one_attached :pdf

  validates :document_type, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :deposit_amount, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: %w[pending_signature pending_payment]) }
  scope :completed, -> { where(status: :completed) }

  def apply_template(template)
    return unless template

    self.document_template = template
    self.body = template.body
    self.metadata = (metadata || {}).merge('template_version' => template.version)
  end

  def pending_signature?
    status == 'pending_signature'
  end

  def pending_payment?
    status == 'pending_payment'
  end

  def completed?
    status == 'completed'
  end

  def payment_required?
    ActiveRecord::Type::Boolean.new.cast(self[:payment_required])
  end

  def signature_required?
    ActiveRecord::Type::Boolean.new.cast(self[:signature_required])
  end

  def mark_status!(new_status, payload = {})
    update!(status: new_status, **payload)
    record_event!("status_changed", new_status: new_status)
  end

  def record_event!(event_type, data = {})
    client_document_events.create!(event_type: event_type, data: data, business: business)
  end

  def ensure_signature_for(role)
    document_signatures.find_by(role: role) || document_signatures.build(role: role)
  end

  def requires_payment_collection?
    payment_required? && deposit_amount.to_f.positive?
  end
end
