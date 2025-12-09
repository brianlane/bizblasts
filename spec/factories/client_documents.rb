FactoryBot.define do
  factory :client_document do
    association :business
    association :tenant_customer
    document_type { 'waiver' }
    status { 'completed' }
    title { "#{document_type.titleize} ##{SecureRandom.hex(4)}" }
    deposit_amount { 0 }
    payment_required { false }
    signature_required { true }
    metadata { {} }
  end
end
# frozen_string_literal: true

FactoryBot.define do
  factory :client_document do
    business
    document_type { 'estimate' }
    status { 'draft' }
    deposit_amount { 10.0 }

    after(:build) do |document|
      document.tenant_customer ||= create(:tenant_customer, business: document.business)
      document.documentable ||= create(:estimate, business: document.business, tenant_customer: document.tenant_customer)
    end
  end
end
