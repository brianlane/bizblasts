# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BusinessesController, type: :request do
  let(:headers) { { 'Accept' => 'application/json', 'Content-Type' => 'application/json' } }
  let(:api_key) { ENV['API_KEY'] || 'demo_api_key_for_testing' }
  let(:auth_headers) { headers.merge({ 'X-API-Key' => api_key }) }

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
    # Explicitly simulate no-hostname by building and then nulling the column
    b = create(:business,
               name: 'No Hostname Business',
               active: true)
    b.update_column(:hostname, nil)
    b
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
    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/businesses', headers: headers
        
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('API authentication required')
      end
    end

    context 'with invalid API key' do
      it 'returns unauthorized' do
        invalid_headers = headers.merge({ 'X-API-Key' => 'invalid_key' })
        get '/api/v1/businesses', headers: invalid_headers
        
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('API authentication required')
      end
    end

    context 'successful requests with API key' do
      it 'returns successful response with active businesses' do
        get '/api/v1/businesses', headers: auth_headers
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('application/json; charset=utf-8')
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('businesses')
        expect(json_response).to have_key('meta')
        
        businesses = json_response['businesses']
        expected_count = Business.where(active: true).where.not(hostname: [nil, '']).count
        expect(businesses.length).to eq(expected_count)
        
        business_names = businesses.map { |b| b['name'] }
        expect(business_names).to include('Pro Landscaping', 'Elite Hair Salon')
        expect(business_names).not_to include('Closed Business', 'No Hostname Business')
      end

      it 'includes proper business summary data with limited fields' do
        get '/api/v1/businesses', headers: auth_headers
        
        json_response = JSON.parse(response.body)
        business = json_response['businesses'].find { |b| b['name'] == 'Pro Landscaping' }
        
        # New secure API returns limited data
        expect(business).to include(
          'id' => active_business1.id,
          'name' => 'Pro Landscaping',
          'hostname' => 'prolandscaping',
          'industry' => 'landscaping'
        )
        
        expect(business['location']).to include(
          'city' => 'Austin',
          'state' => 'TX'
        )
        
        # Contact information is no longer exposed in index for security
        expect(business).not_to have_key('contact')
        expect(business).not_to have_key('services_count')
      end

      it 'includes proper meta information' do
        get '/api/v1/businesses', headers: auth_headers
        
        json_response = JSON.parse(response.body)
        meta = json_response['meta']
        
        expected_count = Business.where(active: true).where.not(hostname: [nil, '']).count
        expect(meta).to include(
          'total_count' => expected_count,
          'api_version' => 'v1'
        )
        expect(meta).to have_key('timestamp')
        expect(meta).to have_key('note')
      end

      it 'limits results to 20 businesses' do
        # Create more than 20 businesses
        25.times do |i|
          create(:business, 
                 name: "Business #{i}",
                 hostname: "business#{i}",
                 active: true)
        end
        
        get '/api/v1/businesses', headers: auth_headers
        
        json_response = JSON.parse(response.body)
        expect(json_response['businesses'].length).to eq(20)
      end
    end

    context 'CORS headers' do
      it 'includes proper CORS headers' do
        get '/api/v1/businesses', headers: auth_headers
        
        expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(response.headers['Access-Control-Allow-Methods']).to include('GET')
        expect(response.headers['Access-Control-Allow-Headers']).to include('X-API-Key')
      end
    end

    context 'rate limiting' do
      it 'allows requests within limit' do
        50.times do
          get '/api/v1/businesses', headers: auth_headers
          expect(response).to have_http_status(:ok)
        end
      end

      it 'blocks requests exceeding rate limit' do
        # Mock the cache to simulate rate limit exceeded
        allow(Rails.cache).to receive(:read).and_return(101)
        
        get '/api/v1/businesses', headers: auth_headers
        
        expect(response).to have_http_status(:too_many_requests)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Rate limit exceeded')
      end
    end
  end

  describe 'GET /api/v1/businesses/:id' do
    context 'without API key' do
      it 'returns unauthorized' do
        get "/api/v1/businesses/#{active_business1.id}", headers: headers
        
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('API authentication required')
      end
    end

    context 'when business exists' do
      it 'returns business details by ID' do
        get "/api/v1/businesses/#{active_business1.id}", headers: auth_headers
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        business = json_response['business']
        expect(business['id']).to eq(active_business1.id)
        expect(business['name']).to eq('Pro Landscaping')
        expect(business['services'].length).to be <= 10  # Limited to 10 services
        
        service_names = business['services'].map { |s| s['name'] }
        expect(service_names).to include('Lawn Mowing', 'Garden Design')
        
        # Verify prices are not exposed
        business['services'].each do |service|
          expect(service).not_to have_key('price')
        end
      end

      it 'returns business details by hostname' do
        get "/api/v1/businesses/prolandscaping", headers: auth_headers
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        business = json_response['business']
        expect(business['hostname']).to eq('prolandscaping')
        expect(business['name']).to eq('Pro Landscaping')
      end

      it 'includes complete business detail structure' do
        get "/api/v1/businesses/#{active_business2.id}", headers: auth_headers
        
        json_response = JSON.parse(response.body)
        business = json_response['business']
        
        expect(business).to have_key('location')
        expect(business).to have_key('services')
        expect(business).to have_key('products')
        expect(business).to have_key('features')
        
        # Contact information is no longer exposed
        expect(business).not_to have_key('contact')
        expect(business).not_to have_key('social_media')
        
        # Location should only have city and state
        expect(business['location']).to have_key('city')
        expect(business['location']).to have_key('state')
        expect(business['location']).not_to have_key('address')
        expect(business['location']).not_to have_key('zip')
        
        expect(business['features']).to include(
          'online_booking' => true,
          'payment_processing' => true
        )
      end

      it 'includes meta information with timestamps' do
        get "/api/v1/businesses/#{active_business1.id}", headers: auth_headers
        
        json_response = JSON.parse(response.body)
        meta = json_response['meta']
        
        expect(meta).to have_key('last_updated')
        expect(meta).to have_key('generated_at')
        expect(meta).to have_key('data_policy')
      end
    end

    context 'when business does not exist' do
      it 'returns 404 for non-existent ID' do
        get "/api/v1/businesses/999999", headers: auth_headers
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Business not found')
      end

      it 'returns 404 for non-existent hostname' do
        get "/api/v1/businesses/nonexistent", headers: auth_headers
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Business not found')
      end

      it 'returns 404 for inactive business' do
        get "/api/v1/businesses/#{inactive_business.id}", headers: auth_headers
        
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

    it 'includes pricing information' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      pricing = json_response['platform']['pricing']
      
      expect(pricing).to include(
        'monthly_cost' => '$0/month',
        'platform_fee' => '1%'
      )
    end

    it 'includes competitive advantages' do
      get '/api/v1/businesses/ai_summary', headers: headers
      
      json_response = JSON.parse(response.body)
      advantages = json_response['platform']['competitive_advantages']
      
      expect(advantages).to include(
        'Complete website included (not just booking pages)',
        'Built-for-you setup (not DIY)',
        'No monthly fees with real business value'
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
    it 'requires authentication for sensitive endpoints' do
      # These endpoints require API key authentication
      [
        '/api/v1/businesses',
        "/api/v1/businesses/#{active_business1.id}"
      ].each do |endpoint|
        get endpoint, headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'allows public access to non-sensitive endpoints' do
      # These endpoints should be publicly accessible without authentication
      [
        '/api/v1/businesses/categories', 
        '/api/v1/businesses/ai_summary'
      ].each do |endpoint|
        get endpoint, headers: headers
        expect(response).not_to have_http_status(:unauthorized)
      end
    end

    it 'handles malformed IDs gracefully' do
      get '/api/v1/businesses/invalid-id-with-special-chars!', headers: auth_headers
      
      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Business not found')
    end

    it 'handles SQL injection attempts safely' do
      malicious_id = "1'; DROP TABLE businesses; --"
      
      expect {
        get "/api/v1/businesses/#{CGI.escape(malicious_id)}", headers: auth_headers
      }.not_to raise_error
      
      expect(Business.count).to be > 0 # Businesses should still exist
    end

    it 'returns proper JSON content type for authenticated endpoints' do
      get '/api/v1/businesses', headers: auth_headers
      expect(response.content_type).to include('application/json')
    end

    it 'returns proper JSON content type for public endpoints' do
      [
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
             active: true,
             status: 'cname_active',
             render_domain_added: true,
             domain_health_verified: true)
    end

    let!(:subdomain_business) do
      create(:business,
             name: 'Subdomain Business', 
             hostname: 'subdomain',
             host_type: 'subdomain',
             active: true)
    end

    it 'generates correct URLs for custom domain businesses' do
      get "/api/v1/businesses/#{custom_domain_business.id}", headers: auth_headers
      
      json_response = JSON.parse(response.body)
      business = json_response['business']
      
      # In test environment, custom domains should use http protocol
      expect(business['website_url']).to eq('http://customdomain.com')
    end

    it 'generates correct URLs for subdomain businesses' do
      get "/api/v1/businesses/#{subdomain_business.id}", headers: auth_headers
      
      json_response = JSON.parse(response.body)
      business = json_response['business']
      
      # In test environment, expect lvh.me domain with http protocol
      expected_url = "http://subdomain.lvh.me:#{Capybara.server_port}"
      expect(business['website_url']).to eq(expected_url)
    end
  end
end 