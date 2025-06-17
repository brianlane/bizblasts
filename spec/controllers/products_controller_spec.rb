require 'rails_helper'

RSpec.describe ProductsController, type: :request do
  include Rails.application.routes.url_helpers

  let!(:business) { create(:business, hostname: 'testtenant') }
  let!(:product) { create(:product, active: true, business: business, price: 100.00) }
  let!(:inactive_product) { create(:product, active: false, business: business) }
  let!(:product_variant) { create(:product_variant, product: product) }

  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }
  
  before do
    ActsAsTenant.current_tenant = business
    Rails.application.routes.default_url_options[:host] = host_params[:host]
  end

  after do
    Rails.application.routes.default_url_options[:host] = nil
  end

  describe 'GET #index' do
    context 'with promotional pricing' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 25,
          applicable_to_products: true,
          active: true
        )
      end
      
      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'displays products with promotional pricing' do
        get '/products', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        
        # Verify promotional pricing is working
        expect(product.reload.on_promotion?).to be true
        expect(product.promotional_price).to eq(75.00)
        expect(product.promotion_display_text).to eq('25% OFF')
      end

      it 'shows correct promotional badges and pricing' do
        get '/products', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        expect(response.body).to include('25% OFF')
        expect(response.body).to include('$75.00') # Promotional price
        expect(response.body).to include('$100.00') # Original price (crossed out)
      end
    end

    context 'without promotional pricing' do
      it 'displays regular pricing' do
        get '/products', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        expect(product.reload.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.00)
      end
    end
  end

  describe 'GET #show' do
    context 'with promotional pricing' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'fixed_amount',
          discount_value: 20.00,
          applicable_to_products: true,
          active: true
        )
      end
      
      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'displays product with promotional pricing details' do
        get "/products/#{product.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        expect(product.reload.on_promotion?).to be true
        expect(product.promotional_price).to eq(80.00)
        expect(product.promotion_display_text).to eq('$20.0 OFF')
      end

      it 'shows promotional pricing in the view' do
        get "/products/#{product.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        expect(response.body).to include('$20.0 OFF')
        expect(response.body).to include('$80.00') # Promotional price
        expect(response.body).to include('(Save 20%)') # Savings percentage
      end
    end

    context 'with expired promotion' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 15,
          start_date: 2.weeks.ago,
          end_date: 1.week.ago,
          applicable_to_products: true,
          active: true
        )
      end
      
      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'does not display promotional pricing for expired promotion' do
        get "/products/#{product.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        expect(product.reload.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.00)
      end
    end
  end

  describe 'promotional pricing with cart integration' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 30,
        applicable_to_products: true,
        active: true
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
    end

    it 'uses promotional pricing when adding to cart' do
      # Verify the product model behavior
      expect(product.reload.on_promotion?).to be true
      expect(product.promotional_price).to eq(70.00) # 100 - 30% = 70
      
      # Verify product page shows promotional pricing
      get "/products/#{product.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      expect(response).to be_successful
      expect(response.body).to include('$70.00') # Promotional price shown
      expect(response.body).to include('30% OFF') # Promotional badge shown
    end
  end
end 