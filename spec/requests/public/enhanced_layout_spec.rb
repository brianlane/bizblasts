require 'rails_helper'

RSpec.describe 'Enhanced public layout', type: :request do
  let(:business) { create(:business, host_type: 'subdomain', subdomain: 'enhancedbiz', hostname: 'enhancedbiz') }

  before do
    ActsAsTenant.current_tenant = business
    create(:service, business: business, name: 'Premium Detail')
  end
  
  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'renders the website builder page using enhanced layout' do
    business.update!(website_layout: 'enhanced')

    host! "#{business.subdomain}.lvh.me"
    get "http://#{business.subdomain}.lvh.me/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('hero-banner-section')
    expect(response.body).to include('testimonial-section')
  end
  
  it 'falls back to the basic home page when layout is reset' do
    business.update!(website_layout: 'enhanced')

    host! "#{business.subdomain}.lvh.me"
    get "http://#{business.subdomain}.lvh.me/"
    expect(response.body).to include('hero-banner-section')

    business.update!(website_layout: 'basic')

    get "http://#{business.subdomain}.lvh.me/"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('hero-banner-section')
    expect(response.body).not_to include('testimonial-section')
  end
end

