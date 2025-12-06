# frozen_string_literal: true

module ClientDocuments
  class DepositService
    def initialize(document)
      @document = document
    end

    def initiate_checkout!(success_url:, cancel_url:)
      session = StripeService.create_client_document_checkout_session(
        document: @document,
        success_url: success_url,
        cancel_url: cancel_url
      )

      checkout_session = session[:session]
      @document.update!(
        checkout_session_id: checkout_session.id,
        payment_intent_id: checkout_session.payment_intent,
        payment_required: true
      )

      session
    end
  end
end
