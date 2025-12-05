# frozen_string_literal: true

module ClientDocuments
  class SignatureService
    def initialize(document)
      @document = document
    end

    def capture!(signer_name:, signer_email:, signature_data:, role: 'client', request: nil)
      signature = @document.document_signatures.create!(
        business: @document.business,
        role: role,
        signer_name: signer_name,
        signer_email: signer_email,
        signature_data: signature_data,
        signed_at: Time.current,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent,
        position: next_position
      )

      @document.update!(signed_at: Time.current)
      @document.record_event!('signature_captured', role: role, signer_email: signer_email)

      signature
    end

    private

    def next_position
      (@document.document_signatures.maximum(:position) || 0) + 1
    end
  end
end
