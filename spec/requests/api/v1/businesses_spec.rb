# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BusinessesController, type: :request do
  let(:headers) { { 'Accept' => 'application/json', 'Content-Type' => 'application/json' } }

  # Test data setup
  let!(:active_business1) do
    create(:business, 
           name: 'Pro Landscaping', 
           hostname: 'prolandscaping',
           industry: 'landscaping',
           description: 'Professional landscaping and lawn care services',
           active: true,
           city: 'Austin',
           state: 'TX',
           phone: '555-0123',
           email: 'info@prolandscaping.com')
  end

  let!(:active_business2) do
    create(:business,
           name: 'Elite Hair Salon',
           hostname: 'elitehair', 
           industry: 'hair_salons',
           description: 'Premium hair styling and treatments',
           active: true,
           city: 'Dallas',
           state: 'TX',
           phone: '555-0456',
           email: 'contact@elitehair.com')
  end

  let!(:inactive_business) do
    create(:business,
           name: 'Closed Business',
           hostname: 'closed',
           active: false)
  end

  let!(:business_without_hostname) do
    create(:business,
           name: 'No Hostname Business',
           hostname: nil,
           active: true)
  end

  # Services and products for testing business details
  let!(:service1) { create(:service, business: active_business1, name: 'Lawn Mowing', price: 50.00, duration: 60) }
  let!(:service2) { create(:service, business: active_business1, name: 'Garden Design', price: 100.00, duration: 120) }
  let!(:product1) { create(:product, business: active_business2, name: 'Hair Shampoo', price: 25.00) }

  before do
    # Ensure services and products are associated
    active_business1.services << [service1, service2] unless active_business1.services.include?(service1)
    active_business2.products << product1 unless active_business2.products.include?(product1)
  end

  describe 'GET /api/v1/businesses' do
    context 'successful requests' do
      it 'returns successful response with active businesses' do
        get '/api/v1/businesses', headers: headers
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('application/json; charset=utf-8')
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('businesses')
        expect(json_response).to have_key('meta')
        
        businesses = json_response['businesses']
        expect(businesses.length).to eq(2) # Only active businesses with hostnames
        
        business_names = businesses.map { |b| b['name'] }
        expect(business_names).to include('Pro Landscaping', 'Elite Hair Salon')
        expect(business_names).not_to include('Closed Business', 'No Hostname Business')
      end

      it 'includes proper business summary data' do
        get '/api/v1/businesses', headers: headers
        
        json_response = JSON.parse(response.body)
        business = json_response['businesses'].find { |b| b['name'] == 'Pro Landscaping' }
        
        expect(business).to include(
          'id' => active_business1.id,
          'name' => 'Pro Landscaping',
          'hostname' => 'prolandscaping',
          'industry' => 'landscaping',
          'services_count' => 2
        )
        
        expect(business['location']).to include(
          'city' => 'Austin',
          'state' => 'TX'
        )
        
        expect(business['contact']).to include(
          'phone' => '555-0123',
          'email' => 'info@prolandscaping.com'
        )
      end

      it 'includes proper meta information' do
        get '/api/v1/businesses', headers: headers
        
        json_response = JSON.parse(response.body)
        meta = json_response['meta']
        
        expect(meta).to include(
          'total_count' => 2,
          'api_version' => 'v1'
        )
        expect(meta).to have_key('timestamp')
      end

      it 'limits results to 50 businesses' do
        # Create more than 50 businesses
        51.times do |i|
          create(:business, 
                 name: "Business #{i}",
                 hostname: "business#{i}",
                 active: true)
        end
        
        get '/api/v1/businesses', headers: headers
        
        json_response = JSON.parse(response.body)
        expect(json_response['businesses'].length).to eq(50)
      end
    end

    context 'CORS headers' do
      it 'includes proper CORS headers' do
        get '/api/v1/businesses', headers: headers
        
        expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(response.headers['Access-Control-Allow-Methods']).to include('GET')
        expect(response.headers['Access-Control-Allow-Headers']).to include('Content-Type')
      end
    end

    context 'rate limiting' do
      it 'allows requests within limit' do
        50.times do
          get '/api/v1/businesses', headers: headers
          expect(response).to have_http_status(:ok)
        end
      end

      it 'blocks requests exceeding rate limit' do
        # Mock the cache to simulate rate limit exceeded
        allow(Rails.cache).to receive(:read).and_return(101)
        
        get '/api/v1/businesses', headers: headers
        
        expect(response).to have_http_status(:too_many_requests)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Rate limit exceeded')
      end
    end
  end

  describe 'GET /api/v1/businesses/:id' do
    context 'when business exists' do
      it 'returns business details by ID' do
        get "/api/v1/businesses/#{active_business1.id}", headers: headers
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        business = json_response['business']
        expect(business['id']).to eq(active_business1.id)
        expect(business['name']).to eq('Pro Landscaping')
        expect(business['services'].length).to eq(2)
        
        service_names = business['services'].map { |s| s['name'] }
        expect(service_names).to include('Lawn Mowing', 'Garden Design')
      end

      it 'returns business details by hostname' do
        get "/api/v1/businesses/prolandscaping", headers: headers
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        business = json_response['business']
        expect(business['hostname']).to eq('prolandscaping')
        expect(business['name']).to eq('Pro Landscaping')
      end

      it 'includes complete business detail structure' do
        get "/api/v1/businesses/#{active_business2.id}", headers: headers
        
        json_response = JSON.parse(response.body)
        business = json_response['business']
        
        expect(business).to have_key('location')
        expect(business).to have_key('contact')
        expect(business).to have_key('social_media')
        expect(business).to have_key('services')
        expect(business).to have_key('products')
        expect(business).to have_key('features')
        
        expect(business['features']).to include(
          'online_booking' => true,
          'payment_processing' => true,
          'staff_management' => true
        )
      end

      it 'includes meta information with timestamps' do
        get "/api/v1/businesses/#{active_business1.id}", headers: headers
        
        json_response = JSON.parse(response.body)
        meta = json_response['meta']
        
        expect(meta).to have_key('last_updated')
        expect(meta).to have_key('generated_at')
      end
    end

    context 'when business does not exist' do
      it 'returns 404 for non-existent ID' do
        get "/api/v1/businesses/999999", headers: headers
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Business not found')
      end

      it 'returns 404 for non-existent hostname' do
        get "/api/v1/businesses/nonexistent", headers: headers
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Business not found')
      end

      it 'returns 404 for inactive business' do
        get "/api/v1/businesses/#{inactive_business.id}", headers: headers
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/businesses/categories' do
    it 'returns successful response with service categories' do
      get '/api/v1/businesses/categories', headers: headers
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      
      expect(json_response).to have_key('service_categories')
      expect(json_response).to have_key('business_types') 
      expect(json_response).to have_key('common_services')
      expect(json_response).to have_key('meta')
    end

    it 'includes expected service categories' do
      get '/api/v1/businesses/categories', headers: headers
      
      json_response = JSON.parse(response.body)
      categories = json_response['service_categories']
      
      category_names = categories.map { |cat| cat['category'] }
      expect(category_names).to include(
        'Home Services',
        'Personal Services',
        'Professional Services',
        'Health & Wellness',
        'Automotive',
        'Events & Entertainment'
      )
    end

    it 'includes category examples' do
      get '/api/v1/businesses/categories', headers: headers
      
      json_response = JSON.parse(response.body)
      home_services = json_response['service_categories'].find { |cat| cat['category'] == 'Home Services' }
      
      expect(home_services['examples']).to include('Landscaping', 'Pool Service', 'Cleaning')
    end

    it 'includes business types array' do
      get '/api/v1/businesses/categories', headers: headers
      
      json_response = JSON.parse(response.body)
      business_types = json_response['business_types']
      
      expect(business_types).to be_an(Array)
      expect(business_types).to include('Service-based businesses that take appointments')
    end

    it 'includes common services with descriptions' do
      get '/api/v1/businesses/categories', headers: headers
      
      json_response = JSON.parse(response.body)
      common_services = json_response['common_services']
      
      website_service = common_services.find { |service| service['name'] == 'Website Creation' }
      expect(website_service).to include(
        'name' => 'Website Creation',
        'description' => 'Professional websites automatically generated for each business'
      )
    end
  end

  describe 'GET /api/v1/businesses/ai_summary' do
    it 'returns successful response with platform summary' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      
      expect(json_response).to have_key('platform')
      expect(json_response).to have_key('meta')
    end

    it 'includes complete platform information' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      platform = json_response['platform']
      
      expect(platform).to include(
        'name' => 'BizBlasts',
        'description' => 'Complete business platform providing professional websites, online booking systems, and payment processing for service-based businesses',
        'target_audience' => 'Service-based businesses that take appointments or bookings'
      )
      
      expect(platform).to have_key('key_features')
      expect(platform).to have_key('pricing')
      expect(platform).to have_key('business_types')
      expect(platform).to have_key('competitive_advantages')
      expect(platform).to have_key('contact')
    end

    it 'includes all pricing tiers' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      pricing = json_response['platform']['pricing']
      
      expect(pricing).to have_key('free_plan')
      expect(pricing).to have_key('standard_plan')
      expect(pricing).to have_key('premium_plan')
      
      free_plan = pricing['free_plan']
      expect(free_plan).to include(
        'cost' => '$0/month',
        'transaction_fee' => '5%'
      )
      expect(free_plan['features']).to be_an(Array)
    end

    it 'includes competitive advantages' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      advantages = json_response['platform']['competitive_advantages']
      
      expect(advantages).to include(
        'Complete website included (not just booking pages)',
        'Built-for-you setup (not DIY)',
        'True free tier with real business value'
      )
    end

    it 'includes contact information' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      contact = json_response['platform']['contact']
      
      expect(contact).to include(
        'website' => 'https://www.bizblasts.com',
        'signup' => 'https://www.bizblasts.com/business/sign_up',
        'support' => 'https://www.bizblasts.com/contact'
      )
    end

    it 'includes meta information optimized for AI' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      meta = json_response['meta']
      
      expect(meta).to include(
        'optimized_for' => 'AI/LLM consumption and citation',
        'version' => '1.0'
      )
      expect(meta).to have_key('last_updated')
    end
  end

  describe 'security and edge cases' do
    it 'skips authentication for all endpoints' do
      # These endpoints should be publicly accessible without authentication
      [
        '/api/v1/businesses',
        '/api/v1/businesses/categories', 
        '/api/v1/businesses/ai_summary',
        "/api/v1/businesses/#{active_business1.id}"
      ].each do |endpoint|
        get endpoint, headers: headers
        expect(response).not_to have_http_status(:unauthorized)
        expect(response).not_to redirect_to(new_user_session_path)
      end
    end

    it 'handles malformed IDs gracefully' do
      get '/api/v1/businesses/invalid-id-with-special-chars!', headers: headers
      
      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Business not found')
    end

    it 'handles SQL injection attempts safely' do
      malicious_id = "1'; DROP TABLE businesses; --"
      
      expect {
        get "/api/v1/businesses/#{CGI.escape(malicious_id)}", headers: headers
      }.not_to raise_error
      
      expect(Business.count).to be > 0 # Businesses should still exist
    end

    it 'returns proper JSON content type for all endpoints' do
      [
        '/api/v1/businesses',
        '/api/v1/businesses/categories',
        '/api/v1/businesses/ai_summary'
      ].each do |endpoint|
        get endpoint, headers: headers
        expect(response.content_type).to include('application/json')
      end
    end
  end

  describe 'business website URL generation' do
    let!(:custom_domain_business) do
      create(:business,
             name: 'Custom Domain Business',
             hostname: 'customdomain.com',
             host_type: 'custom_domain',
             industry: 'landscaping',
             active: true)
    end

    let!(:subdomain_business) do
      create(:business,
             name: 'Subdomain Business', 
             hostname: 'subdomain',
             host_type: 'subdomain',
             active: true)
    end

    it 'generates correct URLs for custom domain businesses' do
      get "/api/v1/businesses/#{custom_domain_business.id}", headers: headers
      
      json_response = JSON.parse(response.body)
      business = json_response['business']
      
      expect(business['website_url']).to eq('https://customdomain.com')
    end

    it 'generates correct URLs for subdomain businesses' do
      get "/api/v1/businesses/#{subdomain_business.id}", headers: headers
      
      json_response = JSON.parse(response.body)
      business = json_response['business']
      
      expect(business['website_url']).to eq('https://subdomain.bizblasts.com')
    end
  end
end 