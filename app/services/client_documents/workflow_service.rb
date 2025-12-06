# frozen_string_literal: true

module ClientDocuments
  class WorkflowService
    def initialize(document)
      @document = document
    end

    def mark_sent!
      @document.update!(status: 'sent', sent_at: Time.current)
      record_event('sent')
    end

    def mark_pending_signature!
      @document.update!(status: 'pending_signature')
      record_event('pending_signature')
    end

    def mark_signature_captured!
      if @document.requires_payment_collection?
        @document.update!(status: 'pending_payment', signed_at: Time.current)
        record_event('pending_payment')
      else
        mark_completed!
      end
    end

    def mark_payment_required!
      @document.update!(status: 'pending_payment')
      record_event('pending_payment')
    end

    def mark_payment_received!(payment_intent_id:, amount_cents:)
      @document.update!(
        status: 'completed',
        payment_intent_id: payment_intent_id,
        deposit_paid_at: Time.current,
        completed_at: Time.current
      )
      record_event('payment_received', amount_cents: amount_cents, payment_intent_id: payment_intent_id)
    end

    def mark_completed!
      @document.update!(status: 'completed', completed_at: Time.current)
      record_event('completed')
    end

    private

    def record_event(event_type, data = {})
      @document.client_document_events.create!(event_type: event_type, data: data, business: @document.business)
    end
  end
end
