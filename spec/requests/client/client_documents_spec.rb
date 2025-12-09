require 'rails_helper'

RSpec.describe "Client::Documents", type: :request do
  let!(:business) { create(:business) }
  let!(:client) { create(:user, :client) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: client.email) }
  let!(:document) do
    ActsAsTenant.without_tenant do
      create(:client_document, business: business, tenant_customer: tenant_customer, document_type: 'waiver', status: 'completed')
    end
  end

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in client
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /my-documents" do
    it "lists documents for the signed-in client" do
      get client_documents_path
      expect(response).to be_successful
      expect(response.body).to include("My Documents")
      expect(response.body).to include(document.title)
    end
  end

  describe "GET /my-documents/:id" do
    it "shows a specific document" do
      get client_document_path(document)
      expect(response).to be_successful
      expect(response.body).to include(document.title)
      expect(response.body).to include(document.status.humanize)
    end
  end
end

