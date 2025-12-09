# frozen_string_literal: true

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

    trait :estimate do
      document_type { 'estimate' }
      status { 'draft' }
      deposit_amount { 10.0 }

      after(:build) do |document|
        document.documentable ||= create(:estimate, business: document.business, tenant_customer: document.tenant_customer)
      end
    end

    trait :rental do
      document_type { 'rental' }
      status { 'pending_signature' }
    end

    trait :pending_signature do
      status { 'pending_signature' }
    end

    trait :pending_payment do
      status { 'pending_payment' }
      payment_required { true }
      deposit_amount { 50.0 }
    end

    trait :void do
      status { 'void' }
    end
  end
end
