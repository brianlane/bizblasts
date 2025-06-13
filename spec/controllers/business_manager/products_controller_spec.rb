require 'rails_helper'

RSpec.describe BusinessManager::ProductsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbiz', hostname: 'testbiz') }
  let(:manager_user) { create(:user, :manager, business: business) }

  before do
    request.host = "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
    sign_in manager_user
  end

  describe 'POST #create' do
    let(:valid_attributes) do
      {
        name: 'Test Product',
        description: 'A test product',
        price: 19.99,
        active: true,
        tips_enabled: true,
        product_type: 'standard'
      }
    end

    it 'creates a new product with tips enabled' do
      expect {
        post :create, params: { product: valid_attributes }
      }.to change(Product, :count).by(1)

      product = Product.last
      expect(product.tips_enabled).to be true
    end

    it 'creates a new product with tips disabled' do
      valid_attributes[:tips_enabled] = false

      post :create, params: { product: valid_attributes }
      
      product = Product.last
      expect(product.tips_enabled).to be false
    end
  end

  describe 'PATCH #update' do
    let!(:product) { create(:product, business: business, tips_enabled: false) }

    it 'updates the product tips_enabled status' do
      patch :update, params: { 
        id: product.id, 
        product: { tips_enabled: true } 
      }

      product.reload
      expect(product.tips_enabled).to be true
    end
  end
end 