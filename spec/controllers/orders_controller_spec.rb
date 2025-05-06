require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let!(:product) { create(:product, business: business) }
  let!(:variant) { create(:product_variant, product: product) }
  let!(:shipping_method) { create(:shipping_method, business: business) }
  let!(:tax_rate) { create(:tax_rate, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
    session[:cart] = { variant.id.to_s => 2 }
  end

  describe 'GET #new' do
    it 'builds order from cart' do
      get :new
      expect(response).to be_successful
      expect(assigns(:order).line_items.size).to eq(1)
    end
  end

  describe 'POST #create' do
    it 'creates order and clears cart' do
      post :create, params: { order: { tenant_customer_id: tenant_customer.id, shipping_method_id: shipping_method.id, tax_rate_id: tax_rate.id } }
      expect(response).to redirect_to(assigns(:order))
      expect(session[:cart]).to eq({})
    end
  end
end 