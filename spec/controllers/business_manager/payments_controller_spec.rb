require 'rails_helper'

RSpec.describe BusinessManager::PaymentsController, type: :controller do
  let(:business) { create(:business) }
  let(:manager)  { create(:user, :manager, business: business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer) }
  let(:payment) { create(:payment, business: business, invoice: invoice, tenant_customer: tenant_customer) }

  before do
    # Ensure requests are scoped to the correct tenant subdomain
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in manager
  end

  describe 'GET #show' do
    it 'assigns the requested payment and renders the show template' do
      get :show, params: { id: payment.id }
      expect(response).to be_successful
      expect(assigns(:payment)).to eq(payment)
      expect(response).to render_template(:show)
    end
  end
end
