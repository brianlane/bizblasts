require 'rails_helper'

RSpec.describe ProductsController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let!(:product) { create(:product, active: true, business: business) }
  let!(:inactive_product) { create(:product, active: false, business: business) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
  end

  describe 'GET #index' do
    it 'returns success' do
      get :index
      expect(response).to be_successful
    end
    it 'assigns only active products' do
      get :index
      expect(assigns(:products)).to include(product)
      expect(assigns(:products)).not_to include(inactive_product)
    end
  end

  describe 'GET #show' do
    it 'returns success' do
      get :show, params: { id: product.id }
      expect(response).to be_successful
    end
    it 'assigns the requested product' do
      get :show, params: { id: product.id }
      expect(assigns(:product)).to eq(product)
    end
  end
end 