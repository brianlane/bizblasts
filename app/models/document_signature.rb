# frozen_string_literal: true

class DocumentSignature < ApplicationRecord
  include TenantScoped

  belongs_to :business
  belongs_to :client_document

  before_validation :set_business_from_document
  before_validation :set_signed_at

  validates :role, presence: true
  validates :signer_name, presence: true

  private

  def set_business_from_document
    self.business_id ||= client_document&.business_id
  end

  def set_signed_at
    self.signed_at ||= Time.current if signature_data.present? && signed_at.nil?
  end
end
