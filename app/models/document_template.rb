# frozen_string_literal: true

class DocumentTemplate < ApplicationRecord
  include TenantScoped

  DOCUMENT_TYPES = [
    ['Estimate approval', 'estimate'],
    ['Rental security deposit', 'rental_security_deposit'],
    ['Experience booking', 'experience_booking'],
    ['Service agreement', 'service'],
    ['Product agreement', 'product'],
    ['Standalone document', 'standalone']
  ].freeze

  # Associations for services/products that use this template
  has_many :services, dependent: :nullify
  has_many :products, dependent: :nullify
  has_many :client_documents, dependent: :nullify

  belongs_to :business

  validates :name, :document_type, :body, presence: true
  validates :document_type, inclusion: { in: DOCUMENT_TYPES.map { |_, value| value } }

  scope :active, -> { where(active: true) }
  scope :for_type, ->(document_type) { where(document_type: document_type) }

  before_create :assign_sequential_version

  def next_version
    version + 1
  end

  private

  def assign_sequential_version
    return if version.present? && version > 1

    max_version = business.document_templates.for_type(document_type).maximum(:version)
    self.version = (max_version || 0) + 1
  end
end
