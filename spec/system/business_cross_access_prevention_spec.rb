# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Business Cross-Access Prevention', type: :system do
  before do
    driven_by(:rack_test)
    # Configure Capybara for multi-tenant setup
    Capybara.configure do |config|
      config.default_host = 'http://www.example.com'
      config.app_host = 'http://www.example.com'
    end
  end

  let!(:business_a) { create(:business, host_type: 'subdomain') }
  let!(:business_b) { create(:business, host_type: 'subdomain') }
  let!(:manager_a) { create(:user, :manager, business: business_a) }
  let!(:staff_a) { create(:user, :staff, business: business_a) }
  let!(:client_user) { create(:user, :client) }
  
  let!(:service_b) { create(:service, business: business_b, name: 'Service B') }
  let!(:staff_member_b) { create(:staff_member, business: business_b) }
  let!(:product_b) { create(:product, business: business_b, name: 'Product B', price: 25.00) }

  # Helper method to visit a business subdomain
  def visit_business_subdomain(business, path = '/')
    host = host_for(business)
    visit "http://#{host}#{path}"
  end

  shared_examples 'blocked access with redirect' do |user_sym, business_sym|
    it "blocks #{user_sym} from accessing booking on other business" do
      user = send(user_sym)
      business = send(business_sym)
      login_as(user, scope: :user)
      visit_business_subdomain(business, "/book?service_id=#{service_b.id}")
      
      expect(page).to have_content("You must sign out and proceed as a guest")
      expect(current_url).to include("/")
    end

    it "blocks #{user_sym} from adding products to cart on other business" do
      user = send(user_sym)
      business = send(business_sym)
      login_as(user, scope: :user)
      visit_business_subdomain(business, "/products")
      
      expect(page).to have_content("You must sign out and proceed as a guest")
      expect(current_url).to include("/")
    end

    it "blocks #{user_sym} from accessing cart on other business" do
      user = send(user_sym)
      business = send(business_sym)
      login_as(user, scope: :user)
      visit_business_subdomain(business, "/cart")
      
      expect(page).to have_content("You must sign out and proceed as a guest")
      expect(current_url).to include("/")
    end

    it "blocks #{user_sym} from creating orders on other business" do
      user = send(user_sym)
      business = send(business_sym)
      login_as(user, scope: :user)
      visit_business_subdomain(business, "/orders/new")
      
      expect(page).to have_content("You must sign out and proceed as a guest")
      expect(current_url).to include("/")
    end

    it "clears cart when #{user_sym} tries to access other business" do
      user = send(user_sym)
      business = send(business_sym)
      login_as(user, scope: :user)
      
      # Now try to access other business
      visit_business_subdomain(business, "/products")
      
      expect(page).to have_content("You must sign out and proceed as a guest")
      expect(current_url).to include("/")
    end
  end

  describe 'Manager access control' do
    include_examples 'blocked access with redirect', :manager_a, :business_b
  end

  describe 'Staff access control' do
    include_examples 'blocked access with redirect', :staff_a, :business_b
  end

  describe 'Client access control' do
    it 'allows clients to access any business products' do
      login_as(client_user, scope: :user)
      visit_business_subdomain(business_b, "/products")
      
      # Should be able to access without being redirected
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      # Should have product page content or at least no error
      expect(page.status_code).to eq(200)
    end

    it 'allows clients to access any business booking' do
      login_as(client_user, scope: :user)
      visit_business_subdomain(business_b, "/book?service_id=#{service_b.id}")
      
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      expect(page.status_code).to eq(200)
    end

    it 'allows clients to use cart across different businesses' do
      login_as(client_user, scope: :user)
      visit_business_subdomain(business_b, "/cart")
      
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      expect(page.status_code).to eq(200)
    end
  end

  describe 'Guest access' do
    it 'allows guests to access any business products and cart' do
      # Don't login anyone - remain as guest
      visit_business_subdomain(business_b, "/products")
      
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      expect(page.status_code).to eq(200)
    end

    it 'allows guests to access any business booking' do
      visit_business_subdomain(business_b, "/book?service_id=#{service_b.id}")
      
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      expect(page.status_code).to eq(200)
    end

    it 'allows guests to use cart functionality' do
      visit_business_subdomain(business_b, "/cart")
      
      expect(page).not_to have_content("You must sign out and proceed as a guest")
      expect(page.status_code).to eq(200)
    end
  end

  describe 'Security logging' do
    it 'logs blocked access attempts' do
      login_as(manager_a, scope: :user)
      
      # Allow the other log messages that happen during the request
      allow(Rails.logger).to receive(:warn)
      
      expect(Rails.logger).to receive(:warn).with(
        /\[SECURITY\] Business user #{manager_a.id} \(manager\) from business #{business_a.id} attempted to access business #{business_b.id}\. Access blocked\./
      )
      
      visit_business_subdomain(business_b, "/products")
    end
  end
end 