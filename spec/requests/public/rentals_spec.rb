# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public::Rentals', type: :request do
  let!(:business) { create(:business, host_type: 'subdomain', show_rentals_section: true) }
  let!(:rental) do
    create(:product, 
      business: business, 
      product_type: :rental, 
      name: 'Public Test Rental',
      price: 50.00,
      security_deposit: 100.00,
      rental_quantity_available: 3,
      rental_category: 'equipment',
      active: true
    )
  end
  
  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end
  
  after do
    ActsAsTenant.current_tenant = nil
  end
  
  describe 'GET /rentals' do
    it 'returns http success' do
      get rentals_path
      expect(response).to have_http_status(:success)
    end
    
    it 'displays rental items' do
      get rentals_path
      expect(response.body).to include(rental.name)
    end
    
    it 'filters by category' do
      get rentals_path(category: 'equipment')
      expect(response).to have_http_status(:success)
    end
    
    it 'does not show inactive rentals' do
      inactive = create(:product, :rental, business: business, active: false, price: 25)
      get rentals_path
      expect(response.body).not_to include(inactive.name)
    end
  end
  
  describe 'GET /rentals/:id' do
    it 'returns http success' do
      get rental_path(rental)
      expect(response).to have_http_status(:success)
    end
    
    it 'displays rental details' do
      get rental_path(rental)
      expect(response.body).to include(rental.name)
      expect(response.body).to include('50') # price
    end
    
    it 'returns 404 for non-rental products' do
      standard = create(:product, business: business, product_type: :standard, price: 25)
      get rental_path(standard)
      expect(response).to have_http_status(:not_found)
    end
  end
  
  describe 'GET /rentals/:id/availability' do
    it 'returns availability calendar as JSON' do
      get availability_rental_path(rental), as: :json
      expect(response).to have_http_status(:success)
      
      data = JSON.parse(response.body)
      expect(data).to be_a(Hash)
      expect(data.keys.first).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end
  
  describe 'GET /rentals/:id/calendar' do
    it 'renders the calendar page' do
      get calendar_rental_path(rental, duration: 60)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Available Time Slots')
    end
  end

  describe 'GET /rentals/:id/available_slots' do
    it 'returns slot data as JSON' do
      travel_to Time.zone.parse('2025-01-01 09:00') do
        get available_slots_rental_path(rental, duration: 60, date: Date.current), as: :json
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['slots']).to be_an(Array)
      end
    end
  end

  describe 'GET /rentals/:id/book' do
    let(:start_time) { 2.days.from_now.change(hour: 10).iso8601 }

    it 'redirects if no slot provided' do
      get book_rental_path(rental)
      expect(response).to redirect_to(calendar_rental_path(rental, duration: 60, quantity: 1))
    end
    
    it 'returns http success when slot params are included' do
      get book_rental_path(rental, start_time: start_time, duration: 60)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Confirm Slot')
    end
  end
  
  describe 'POST /rentals/:id/create_booking' do
    let(:start_time) { 2.days.from_now.change(hour: 10) }
    let(:customer_params) do
      {
        customer: {
          first_name: 'John',
          last_name: 'Doe',
          email: 'john@example.com',
          phone: '555-1234'
        },
        rental_booking: {
          start_time: start_time.iso8601,
          duration_mins: 120,
          quantity: 1
        }
      }
    end
    
    it 'creates a new booking' do
      expect {
        post create_booking_rental_path(rental), params: customer_params
      }.to change(RentalBooking, :count).by(1)
    end
    
    it 'creates or finds a customer' do
      expect {
        post create_booking_rental_path(rental), params: customer_params
      }.to change(TenantCustomer, :count).by(1)
    end
    
    it 'redirects to payment if deposit required' do
      post create_booking_rental_path(rental), params: customer_params
      booking = RentalBooking.last
      expect(response).to redirect_to(pay_deposit_rental_booking_path(booking))
    end
    
    context 'when logged in as client' do
      let(:client) { create(:user, :client, business: business, email: 'client@example.com') }
      
      before { sign_in client }
      
      it 'uses the logged in user for customer' do
        post create_booking_rental_path(rental), params: {
          rental_booking: {
            start_time: start_time.iso8601,
            duration_mins: 60,
            quantity: 1
          }
        }
        
        booking = RentalBooking.last
        expect(booking).to be_present
        expect(booking.tenant_customer.email).to eq('client@example.com')
      end
    end
  end
end
