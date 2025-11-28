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
      inactive = create(:product, business: business, product_type: :rental, active: false, price: 25)
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
  
  describe 'GET /rentals/:id/book' do
    it 'returns http success' do
      get book_rental_path(rental)
      expect(response).to have_http_status(:success)
    end
    
    it 'displays the booking form' do
      get book_rental_path(rental)
      expect(response.body).to include('Book')
      expect(response.body).to include(rental.name)
    end
  end
  
  describe 'POST /rentals/:id/create_booking' do
    let(:customer_params) do
      {
        customer: {
          first_name: 'John',
          last_name: 'Doe',
          email: 'john@example.com',
          phone: '555-1234'
        },
        rental_booking: {
          start_time: 2.days.from_now.iso8601,
          end_time: 4.days.from_now.iso8601,
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
            start_time: 2.days.from_now.iso8601,
            end_time: 4.days.from_now.iso8601,
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
