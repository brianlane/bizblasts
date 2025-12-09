module Client
  class DocumentsController < ApplicationController
    helper ClientDocumentsHelper
    before_action :authenticate_user!
    before_action :ensure_client_user
    before_action :set_tenant_customer_ids
    before_action :set_document, only: [:show]

    def index
      @documents = ActsAsTenant.without_tenant do
        ClientDocument
          .where(tenant_customer_id: @tenant_customer_ids)
          .includes(:business)
          .order(updated_at: :desc)
      end
    end

    def show; end

    private

    def ensure_client_user
      return if current_user&.client?
      redirect_to root_path, alert: 'Access denied.'
    end

    def set_tenant_customer_ids
      @tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
      if @tenant_customer_ids.empty?
        redirect_to dashboard_path, alert: 'No documents found for your account.' and return
      end
    end

    def set_document
      @document = ActsAsTenant.without_tenant do
        ClientDocument.includes(:business).find_by(id: params[:id], tenant_customer_id: @tenant_customer_ids)
      end

      return if @document
      redirect_to client_documents_path, alert: 'Document not found.'
    end
  end
end

