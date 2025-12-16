# frozen_string_literal: true

module Public
  class ClientDocumentsController < BaseController
    skip_before_action :set_tenant

    before_action :set_document

    def show
      @business = @document.business
      @signature = @document.ensure_signature_for('customer')

      # Mark as viewed if not already signed
      if @document.status == 'sent'
        @document.update(status: 'pending_signature')
      end
    end

    def sign
      signature = @document.ensure_signature_for('customer')
      
      # Validate signature data
      unless params[:signature_data].present?
        redirect_to public_client_document_path(token: @document.id), alert: 'Signature is required.'
        return
      end

      ActiveRecord::Base.transaction do
        # Save the signature
        signature.update!(
          signature_data: params[:signature_data],
          signed_at: Time.current,
          signer_name: params[:signer_name],
          signer_email: params[:signer_email]
        )

        # Update document status
        if @document.payment_required? && @document.deposit_amount.to_f > 0
          @document.update!(status: 'pending_payment', signed_at: Time.current)
          # TODO: Redirect to payment
          redirect_to public_client_document_path(token: @document.id), notice: 'Document signed. Please complete payment.'
        else
          @document.update!(status: 'completed', signed_at: Time.current, completed_at: Time.current)
          
          # Notify business
          ClientDocumentMailer.signed_notification(@document).deliver_later
          
          redirect_to public_client_document_path(token: @document.id), notice: 'Thank you! Document signed successfully.'
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to public_client_document_path(token: @document.id), alert: "Error saving signature: #{e.message}"
    end

    def download_pdf
      if @document.pdf.attached?
        redirect_to rails_blob_path(@document.pdf, disposition: 'attachment'), allow_other_host: true
      else
        redirect_to public_client_document_path(token: @document.id), alert: 'PDF not available.'
      end
    end

    private

    def set_document
      @document = ClientDocument.find_by(id: params[:token])
      
      if @document.nil?
        render plain: 'Document not found', status: :not_found
        return
      end

      # Set tenant for proper scoping
      ActsAsTenant.current_tenant = @document.business
    end
  end
end

