# frozen_string_literal: true

class ClientDocumentMailer < ApplicationMailer
  # Sends a standalone document to a customer for signature
  def send_document(client_document, customer_email, customer_name)
    @client_document = client_document
    @business = client_document.business
    @customer_name = customer_name

    # Generate the document access URL using secure token
    @document_url = public_client_document_url(
      token: client_document.token,
      host: "#{@business.subdomain}.#{Rails.application.config.main_domain}",
      protocol: 'https'
    )

    mail(
      to: customer_email,
      from: @business.email,
      subject: "Document for your signature: #{client_document.title || 'Agreement'}"
    )
  end

  # Notify business when customer signs a document
  def signed_notification(client_document)
    @client_document = client_document
    @business = client_document.business
    @customer = client_document.tenant_customer

    mail(
      to: @business.email,
      subject: "Document signed: #{client_document.title || 'Agreement'}"
    )
  end
end

