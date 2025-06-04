# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Layout Navigation', type: :request do
  let(:business) { FactoryBot.create(:business, hostname: 'testbiz') }
  let(:service) { FactoryBot.create(:service, business: business) }
  let(:manager) { FactoryBot.create(:user, :manager, business: business) }
  let(:staff) { FactoryBot.create(:user, :staff, business: business) }
  let(:client) { FactoryBot.create(:user, :client) }

  describe 'Client Dashboard Navigation Menu' do
    context 'when business user (manager) visits their own business subdomain' do
      before do
        sign_in manager
        host! "#{business.hostname}.lvh.me"
      end

      it 'does not show client navigation menu on /book page' do
        get '/book', params: { service_id: service.id }
        
        # Should not show the client navigation menu
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('My Transactions')
        expect(response.body).not_to include('Book Appointment')
        expect(response.body).not_to include('nav-link-professional')
      end

      it 'does not show client navigation menu on /calendar page' do
        get '/calendar'
        
        # Should not show the client navigation menu
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('My Transactions') 
        expect(response.body).not_to include('Book Appointment')
        expect(response.body).not_to include('nav-link-professional')
      end
    end

    context 'when business user (staff) visits their own business subdomain' do
      before do
        sign_in staff
        host! "#{business.hostname}.lvh.me"
      end

      it 'does not show client navigation menu on /book page' do
        get '/book', params: { service_id: service.id }
        
        # Should not show the client navigation menu
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('My Transactions')
        expect(response.body).not_to include('Book Appointment')
        expect(response.body).not_to include('nav-link-professional')
      end

      it 'does not show client navigation menu on /calendar page' do
        get '/calendar'
        
        # Should not show the client navigation menu
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('My Transactions')
        expect(response.body).not_to include('Book Appointment')
        expect(response.body).not_to include('nav-link-professional')
      end
    end

    context 'when client user visits a business subdomain' do
      before do
        sign_in client
        host! "#{business.hostname}.lvh.me"
      end

      it 'shows client navigation menu on /book page' do
        get '/book', params: { service_id: service.id }
        
        # Should show the client navigation menu for client users
        expect(response.body).to include('My Bookings')
        expect(response.body).to include('My Transactions')
        expect(response.body).to include('Book Appointment')
      end

      it 'shows client navigation menu on /calendar page' do
        get '/calendar'
        
        # Should show the client navigation menu for client users
        expect(response.body).to include('My Bookings')
        expect(response.body).to include('My Transactions')
        expect(response.body).to include('Book Appointment')
      end
    end

    context 'when business user visits different business subdomain' do
      let(:other_business) { FactoryBot.create(:business, hostname: 'otherbiz') }
      
      before do
        sign_in manager
        host! "#{other_business.hostname}.lvh.me"
      end

      it 'does not show client navigation menu when visiting different business subdomain' do
        get '/calendar'
        
        # Business users should never see client navigation menu anywhere
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('My Transactions')
        expect(response.body).not_to include('Book Appointment')
        expect(response.body).not_to include('nav-link-professional')
      end
    end

    context 'when business user visits main domain' do
      before do
        sign_in manager
        host! 'lvh.me'
      end

      it 'does not show client navigation menu on main domain' do
        get root_path
        
        # Business users should never see client navigation menu anywhere
        expect(response.body).not_to include('My Bookings')
        expect(response.body).not_to include('nav-link-professional')
      end
    end
  end

  describe 'Manage Business Button' do
    context 'when business user (manager) is on their own business subdomain' do
      before do
        sign_in manager
        host! "#{business.hostname}.lvh.me"
      end

      it 'shows "Manage Business" button pointing to business dashboard' do
        get '/calendar'
        
        # Should show Manage Business button
        expect(response.body).to include('Manage Business')
        # Should link to the business manager dashboard path
        expect(response.body).to include('href="/manage/dashboard"')
      end

      it 'allows access to the business dashboard' do
        get '/manage/dashboard'
        
        # Should successfully access the business dashboard
        expect(response).to have_http_status(:success)
      end
    end

    context 'when business user (staff) is on their own business subdomain' do
      before do
        sign_in staff
        host! "#{business.hostname}.lvh.me"
      end

      it 'shows "Manage Business" button pointing to business dashboard' do
        get '/calendar'
        
        # Should show Manage Business button
        expect(response.body).to include('Manage Business')
        # Should link to the business manager dashboard path
        expect(response.body).to include('href="/manage/dashboard"')
      end

      it 'allows access to the business dashboard' do
        get '/manage/dashboard'
        
        # Should successfully access the business dashboard
        expect(response).to have_http_status(:success)
      end
    end

    context 'when business user (manager) is on main domain' do
      before do
        sign_in manager
        host! 'lvh.me'
      end

      it 'shows "Manage Business" button with redirect to their business subdomain' do
        get root_path
        
        # Should show Manage Business button
        expect(response.body).to include('Manage Business')
        # Should link to their business subdomain dashboard
        expected_url = "http://#{business.hostname}.lvh.me:80/manage/dashboard"
        expect(response.body).to include("href=\"#{expected_url}\"")
      end
    end

    context 'when business user (manager) visits different business subdomain' do
      let(:other_business) { FactoryBot.create(:business, hostname: 'otherbiz') }
      
      before do
        sign_in manager
        host! "#{other_business.hostname}.lvh.me"
      end

      it 'shows "Manage Business" button redirecting to their own business subdomain' do
        get '/calendar'
        
        # Should show Manage Business button
        expect(response.body).to include('Manage Business')
        # Should link to their own business subdomain dashboard, not the current one
        expected_url = "http://#{business.hostname}.lvh.me:80/manage/dashboard"
        expect(response.body).to include("href=\"#{expected_url}\"")
      end
    end

    context 'when client user visits a business subdomain' do
      before do
        sign_in client
        host! "#{business.hostname}.lvh.me"
      end

      it 'shows "Dashboard" button pointing to main domain dashboard' do
        get '/calendar'
        
        # Should show Dashboard button (not Manage Business)
        expect(response.body).to include('Dashboard')
        expect(response.body).not_to include('Manage Business')
        # Should redirect to main domain dashboard
        expect(response.body).to include('href="http://lvh.me/dashboard"')
      end
    end
  end
end