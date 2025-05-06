require 'rails_helper'

RSpec.describe LineItemsController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let!(:product) { create(:product, business: business) }
  let!(:variant) { create(:product_variant, product: product) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
  end

  describe 'POST #create' do
    it 'adds item to cart and returns success' do
      post :create, params: { product_variant_id: variant.id, quantity: 2 }
      expect(response).to be_successful
      expect(session[:cart][variant.id.to_s]).to eq(2)
    end
  end

  describe 'PATCH #update' do
    before { session[:cart] = { variant.id.to_s => 2 } }
    it 'updates item quantity in cart' do
      patch :update, params: { id: variant.id, quantity: 5 }
      expect(response).to be_successful
      expect(session[:cart][variant.id.to_s]).to eq(5)
    end
    it 'removes item if quantity is zero' do
      patch :update, params: { id: variant.id, quantity: 0 }
      expect(response).to be_successful
      expect(session[:cart][variant.id.to_s]).to be_nil
    end
  end

  describe 'DELETE #destroy' do
    before { session[:cart] = { variant.id.to_s => 2 } }
    it 'removes item from cart' do
      delete :destroy, params: { id: variant.id }
      expect(response).to be_successful
      expect(session[:cart][variant.id.to_s]).to be_nil
    end
  end
end 