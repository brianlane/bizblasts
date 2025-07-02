require 'rails_helper'

RSpec.describe Public::ServicesController, type: :request do
  include Rails.application.routes.url_helpers

  let!(:business) { create(:business) }
  let!(:service) { create(:service, business: business, price: 150.00, name: 'Test Service') }
  let!(:staff_member) { create(:staff_member, business: business) }
  
  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }
  
  before do
    ActsAsTenant.current_tenant = business
    Rails.application.routes.default_url_options[:host] = host_params[:host]
  end

  after do
    Rails.application.routes.default_url_options[:host] = nil
  end

  describe 'GET #show' do
    context 'with promotional pricing' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 20,
          applicable_to_services: true,
          start_date: 1.week.ago,
          end_date: 1.week.from_now,
          active: true
        )
      end
      
      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'displays service with promotional pricing details' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        
        # Test the service data is loaded correctly
        service.reload
        expect(service.on_promotion?).to be true
        expect(service.promotional_price).to eq(120.00) # 150 - 20% = 120
        expect(service.promotion_display_text).to eq('20% OFF')
      end

      it 'shows promotional pricing and badges in the view' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response.body).to include('20% OFF')
        expect(response.body).to include('$120.00') # Promotional price
        expect(response.body).to include('$150.00') # Original price (should be crossed out)
        expect(response.body).to include('Save 20%') # Savings percentage
      end

      it 'shows promotional badge styling' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        # Test for promotional badge classes
        expect(response.body).to include('bg-red-100') # Promotional badge styling
        expect(response.body).to include('line-through') # Original price styling
        expect(response.body).to include('text-red-800') # Badge text color
      end
    end

    context 'with fixed amount promotional pricing' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'fixed_amount',
          discount_value: 25.00,
          applicable_to_services: true,
          start_date: 1.week.ago,
          end_date: 1.week.from_now,
          active: true
        )
      end
      
      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'displays fixed amount promotional pricing' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        service.reload
        expect(service.promotional_price).to eq(125.00) # 150 - 25 = 125
        expect(service.promotion_display_text).to eq('$25.0 OFF')
        expect(service.promotion_discount_amount).to eq(25.00)
        
        expect(response.body).to include('$25.0 OFF')
        expect(response.body).to include('$125.00')
      end
    end

    context 'without promotional pricing' do
      it 'displays regular service pricing' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response).to be_successful
        
        service.reload
        expect(service.on_promotion?).to be false
        expect(service.promotional_price).to eq(150.00)
        
        expect(response.body).to include('Test Service')
        expect(response.body).to include('$150.00')
      end

      it 'does not show promotional elements' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        expect(response.body).not_to include('% OFF')
        expect(response.body).not_to include('line-through')
        expect(response.body).not_to include('Save')
      end
    end

    context 'expired promotion' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 20,
          applicable_to_services: true,
          start_date: 2.weeks.ago,
          end_date: 1.week.ago,
          active: true
        )
      end
      
      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'does not apply expired promotional pricing' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        service.reload
        expect(service.on_promotion?).to be false
        expect(service.promotional_price).to eq(150.00)
        
        expect(response.body).not_to include('% OFF')
        expect(response.body).to include('$150.00')
      end
    end

    context 'inactive promotion' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage', 
          discount_value: 20,
          applicable_to_services: true,
          start_date: 1.week.ago,
          end_date: 1.week.from_now,
          active: false
        )
      end
      
      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'does not apply inactive promotional pricing' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        service.reload
        expect(service.on_promotion?).to be false
        expect(service.promotional_price).to eq(150.00)
        
        expect(response.body).not_to include('% OFF')
        expect(response.body).to include('$150.00')
      end
    end

    context 'usage limited promotion' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 20,
          applicable_to_services: true,
          start_date: 1.week.ago,
          end_date: 1.week.from_now,
          active: true,
          usage_limit: 1,
          current_usage: 1
        )
      end
      
      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'does not apply usage-limited promotional pricing when limit reached' do
        get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        
        service.reload
        expect(service.on_promotion?).to be false
        expect(service.promotional_price).to eq(150.00)
        
        expect(response.body).not_to include('% OFF')
        expect(response.body).to include('$150.00')
      end
    end
  end

  describe 'promotional pricing with booking integration' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'fixed_amount',
        discount_value: 37.50,
        applicable_to_services: true,
        start_date: 1.week.ago,
        end_date: 1.week.from_now,
        active: true
      )
    end
    
    before do
      promotion.promotion_services.create!(service: service)
    end

    it 'uses promotional pricing when creating bookings' do
      get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      # Check that promotional price is displayed in booking context
      expect(response.body).to include('$112.50') # 150 - 37.50 = 112.50
      expect(response.body).to include('$37.5 OFF')
    end
  end

  describe 'mobile-responsive promotional display' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 15,
        applicable_to_services: true,
        start_date: 1.week.ago,
        end_date: 1.week.from_now,
        active: true
      )
    end
    
    before do
      promotion.promotion_services.create!(service: service)
    end

    it 'displays promotional pricing with mobile-friendly classes' do
      get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      # Check for responsive classes
      expect(response.body).to include('sm:') # Mobile responsive classes
      expect(response.body).to include('text-xs') # Small text classes for mobile
      expect(response.body).to include('px-3 py-1') # Compact padding for mobile badges
    end
  end

  describe 'accessibility features' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 25,
        applicable_to_services: true,
        start_date: 1.week.ago,
        end_date: 1.week.from_now,
        active: true
      )
    end
    
    before do
      promotion.promotion_services.create!(service: service)
    end

    it 'includes screen reader accessible promotional content' do
      get "/services/#{service.id}", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      
      # Check that promotional information is clearly structured
      expect(response.body).to include('25% OFF')
      expect(response.body).to include('Save 25%')
      
      # Check pricing structure is clear
      expect(response.body).to include('$112.50') # Promotional price
      expect(response.body).to include('$150.00') # Original price
    end
  end
end 