# frozen_string_literal: true

class ClientDocumentEvent < ApplicationRecord
  include TenantScoped

  belongs_to :business
  belongs_to :client_document

  validates :event_type, presence: true

  before_validation :set_business_from_document

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      business_id
      client_document_id
      event_type
      message
      actor_type
      actor_id
      ip_address
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business client_document]
  end

  private

  def set_business_from_document
    self.business_id ||= client_document&.business_id
  end
end
