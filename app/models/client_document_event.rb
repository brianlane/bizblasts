# frozen_string_literal: true

class ClientDocumentEvent < ApplicationRecord
  include TenantScoped

  belongs_to :business
  belongs_to :client_document

  validates :event_type, presence: true

  before_validation :set_business_from_document

  private

  def set_business_from_document
    self.business_id ||= client_document&.business_id
  end
end
