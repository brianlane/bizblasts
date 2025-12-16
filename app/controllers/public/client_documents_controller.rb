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
      # Validate signature data before starting transaction
      unless params[:signature_data].present?
        redirect_to public_client_document_path(token: @document.token), alert: 'Signature is required.'
        return
      end

      result = nil
      
      ActiveRecord::Base.transaction do
        # Lock the document to prevent race conditions (TOCTOU)
        @document.lock!
        
        # Re-check signable? after acquiring lock to prevent double-signing
        unless @document.signable?
          alert_message = if @document.completed?
                            'This document has already been signed.'
                          elsif @document.status == 'void'
                            'This document is no longer valid.'
                          elsif @document.status == 'draft'
                            'This document is not ready for signing.'
                          elsif !@document.signature_required?
                            'This document does not require a signature.'
                          else
                            'This document cannot be signed at this time.'
                          end
          result = { redirect: public_client_document_path(token: @document.token), alert: alert_message }
          raise ActiveRecord::Rollback
        end

        signature = @document.ensure_signature_for('customer')
        
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
          result = { redirect: public_client_document_path(token: @document.token), notice: 'Document signed. Please complete payment.' }
        else
          @document.update!(status: 'completed', signed_at: Time.current, completed_at: Time.current)
          result = { redirect: public_client_document_path(token: @document.token), notice: 'Thank you! Document signed successfully.', notify: true }
        end
      end

      # Handle result after transaction completes
      if result
        # Send notification email outside transaction if document was completed
        if result[:notify]
          ClientDocumentMailer.signed_notification(@document).deliver_later
        end
        
        if result[:alert]
          redirect_to result[:redirect], alert: result[:alert]
        else
          redirect_to result[:redirect], notice: result[:notice]
        end
      else
        # Transaction was rolled back without setting result
        redirect_to public_client_document_path(token: @document.token), alert: 'An error occurred. Please try again.'
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to public_client_document_path(token: @document.token), alert: "Error saving signature: #{e.message}"
    end

    def download_pdf
      if @document.pdf.attached?
        redirect_to rails_blob_path(@document.pdf, disposition: 'attachment'), allow_other_host: true
      else
        redirect_to public_client_document_path(token: @document.token), alert: 'PDF not available.'
      end
    end

    private

    def set_document
      # Use secure token instead of predictable ID
      @document = ClientDocument.find_by(token: params[:token])
      
      if @document.nil?
        render plain: 'Document not found', status: :not_found
        return
      end

      # Set tenant for proper scoping
      ActsAsTenant.current_tenant = @document.business
    end
  end
end

