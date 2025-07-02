require 'rails_helper'

RSpec.describe 'BusinessManager::Promotions', type: :request do
  include Rails.application.routes.url_helpers

  let!(:business) { create(:business) }
  let!(:business_user) { create(:user, :manager, business: business) }
  let!(:promotion) { create(:promotion, business: business) }
  let!(:product1) { create(:product, business: business) }
  let!(:product2) { create(:product, business: business) }
  let!(:service1) { create(:service, business: business) }
  let!(:service2) { create(:service, business: business) }

  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }
  
  before do
    sign_in business_user
    Rails.application.routes.default_url_options[:host] = host_params[:host]
    ActsAsTenant.current_tenant = business
  end

  after do
    Rails.application.routes.default_url_options[:host] = nil
  end

  describe 'GET /manage/promotions' do
    let!(:active_promotion) do
      create(:promotion, :code_based,
        business: business,
        name: 'Summer Sale',
        code: 'SUMMER20',
        discount_type: 'percentage',
        discount_value: 20,
        active: true
      )
    end
    
    let!(:inactive_promotion) do
      create(:promotion, :code_based,
        business: business,
        name: 'Winter Sale',
        code: 'WINTER15',
        discount_type: 'fixed_amount',
        discount_value: 15,
        active: false
      )
    end

    it 'displays all promotions for the business' do
      get '/manage/promotions', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Summer Sale')
      expect(response.body).to include('Winter Sale')
      expect(response.body).to include('SUMMER20')
      expect(response.body).to include('WINTER15')
    end

    it 'shows promotion status indicators' do
      get '/manage/promotions', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('Deactivate') # For active promotion showing deactivate button
      expect(response.body).to include('Activate') # For inactive promotion showing activate button
    end

    it 'shows promotional discount information' do
      get '/manage/promotions', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('20% OFF') # Percentage discount
      expect(response.body).to include('10% OFF') # Another percentage discount from active promotions
    end
  end

  describe 'GET /manage/promotions/new' do
    it 'displays the new promotion form' do
      get '/manage/promotions/new', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('New Promotion')
      expect(response.body).to include('form')
    end

    it 'includes product and service selection options' do
      get '/manage/promotions/new', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('Products')
      expect(response.body).to include('Services')
      expect(response.body).to include(product1.name)
      expect(response.body).to include(service1.name)
    end

    it 'includes discount type options' do
      get '/manage/promotions/new', params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('Percentage')
      expect(response.body).to include('Fixed Amount')
    end
  end

  describe 'POST /manage/promotions' do
    context 'with valid parameters' do
      let(:valid_params) do
        {
          promotion: {
            name: 'Flash Sale',
            code: 'FLASH30',
            discount_type: 'percentage',
            discount_value: 30,
            start_date: Date.current,
            end_date: 1.week.from_now,
            usage_limit: 100,
            active: true,
            applicable_to_products: true,
            applicable_to_services: false,
            allow_discount_codes: false,
            product_ids: [product1.id]
          }
        }
      end

      it 'creates a new promotion successfully' do
        expect {
          post '/manage/promotions', params: valid_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        }.to change(Promotion, :count).by(1)
        
        promotion = Promotion.last
        expect(response).to redirect_to("/manage/promotions/#{promotion.id}")
      end

      it 'creates promotion with associated products' do
        post '/manage/promotions', params: valid_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        promotion = Promotion.last
        expect(promotion.products).to include(product1)
        expect(promotion.applicable_to_products).to be true
        expect(promotion.applicable_to_services).to be false
      end

      it 'creates promotion with correct attributes' do
        post '/manage/promotions', params: valid_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        promotion = Promotion.last
        expect(promotion.name).to eq('Flash Sale')
        expect(promotion.code).to eq('FLASH30')
        expect(promotion.discount_type).to eq('percentage')
        expect(promotion.discount_value).to eq(30)
        expect(promotion.business).to eq(business)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_params) do
        {
          promotion: {
            name: '',
            code: '',
            discount_type: 'percentage',
            discount_value: -10
          }
        }
      end

      it 'does not create a promotion with invalid data' do
        expect {
          post '/manage/promotions', params: invalid_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        }.not_to change(Promotion, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'displays validation errors' do
        post '/manage/promotions', params: invalid_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response.body).to include('error')
      end
    end
  end

  describe 'GET /manage/promotions/:id' do
    let!(:promotion) do
      create(:promotion, :code_based,
        business: business,
        name: 'Holiday Sale',
        code: 'HOLIDAY25',
        discount_type: 'percentage',
        discount_value: 25
      )
    end

    before do
      promotion.promotion_products.create!(product: product1)
      promotion.promotion_services.create!(service: service1)
    end

    it 'displays the promotion details' do
      get "/manage/promotions/#{promotion.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Holiday Sale')
      expect(response.body).to include('HOLIDAY25')
      expect(response.body).to include('25%')
    end

    it 'shows associated products and services' do
      get "/manage/promotions/#{promotion.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include(product1.name)
      expect(response.body).to include(service1.name)
    end

    it 'displays usage statistics' do
      get "/manage/promotions/#{promotion.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('Usage Statistics')
      expect(response.body).to include('Total Usage')
    end
  end

  describe 'GET /manage/promotions/:id/edit' do
    let!(:promotion) do
      create(:promotion, :code_based,
        business: business,
        name: 'Black Friday',
        code: 'BF2024'
      )
    end

    it 'displays the edit promotion form' do
      get "/manage/promotions/#{promotion.id}/edit", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Edit Promotion')
      expect(response.body).to include('Black Friday')
      expect(response.body).to include('BF2024')
    end

    it 'pre-populates form with existing data' do
      get "/manage/promotions/#{promotion.id}/edit", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include("value=\"#{promotion.name}\"")
      expect(response.body).to include("value=\"#{promotion.code}\"")
    end
  end

  describe 'PATCH /manage/promotions/:id' do
    let!(:promotion) do
      create(:promotion, :code_based,
        business: business,
        name: 'Old Name',
        code: 'OLDCODE',
        discount_value: 10
      )
    end

    context 'with valid parameters' do
      let(:update_params) do
        {
          promotion: {
            name: 'Updated Name',
            discount_value: 20,
            service_ids: [service1.id]
          }
        }
      end

      it 'updates the promotion successfully' do
        patch "/manage/promotions/#{promotion.id}", params: update_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to redirect_to("/manage/promotions/#{promotion.id}")
        promotion.reload
        expect(promotion.name).to eq('Updated Name')
        expect(promotion.discount_value).to eq(20)
      end

      it 'updates associated services' do
        patch "/manage/promotions/#{promotion.id}", params: update_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        promotion.reload
        expect(promotion.services).to include(service1)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_update_params) do
        {
          promotion: {
            name: '',
            discount_value: -5
          }
        }
      end

      it 'does not update with invalid data' do
        patch "/manage/promotions/#{promotion.id}", params: invalid_update_params, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to have_http_status(:unprocessable_entity)
        promotion.reload
        expect(promotion.name).to eq('Old Name')
      end
    end
  end

  describe 'DELETE /manage/promotions/:id' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        name: 'To Be Deleted'
      )
    end

    it 'deletes the promotion successfully' do
      expect {
        delete "/manage/promotions/#{promotion.id}", headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      }.to change(Promotion, :count).by(-1)
      
      expect(response).to redirect_to('/manage/promotions')
    end

    it 'shows confirmation message' do
      delete "/manage/promotions/#{promotion.id}", headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to redirect_to('/manage/promotions')
      expect(flash[:notice]).to eq('Promotion was successfully deleted.')
    end
  end

  describe 'promotion activation/deactivation' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        active: false
      )
    end

    it 'allows toggling promotion status' do
      patch "/manage/promotions/#{promotion.id}", params: {
        promotion: { active: true }
      }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      promotion.reload
      expect(promotion.active?).to be true
    end
  end

  describe 'promotional pricing preview' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 15,
        applicable_to_products: true
      )
    end

    before do
      promotion.promotion_products.create!(product: product1)
    end

    it 'shows promotional pricing preview in promotion details' do
      get "/manage/promotions/#{promotion.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response.body).to include('Preview')
      expect(response.body).to include('15% OFF')
      expect(response.body).to include('Summer Sale') # Promotion name in preview
    end
  end

  describe 'bulk operations' do
    let!(:promotion1) { create(:promotion, business: business, active: true) }
    let!(:promotion2) { create(:promotion, business: business, active: true) }

    it 'allows bulk deactivation of promotions' do
      patch '/manage/promotions/bulk_deactivate', params: {
        promotion_ids: [promotion1.id, promotion2.id]
      }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      expect(response).to redirect_to('/manage/promotions')
      [promotion1, promotion2].each do |promo|
        promo.reload
        expect(promo.active?).to be false
      end
    end
  end
end 