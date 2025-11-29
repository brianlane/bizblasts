# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::Rentals', type: :request do
  let!(:business) { create(:business, subdomain: 'rentaltest', host_type: 'subdomain') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:rental) do
    create(:product, 
      business: business, 
      product_type: :rental, 
      name: 'Test Rental Item',
      price: 50.00,
      security_deposit: 100.00,
      rental_quantity_available: 5,
      rental_category: 'equipment'
    )
  end
  
  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in manager
  end
  
  describe 'GET /manage/rentals' do
    it 'returns http success' do
      get business_manager_rentals_path
      expect(response).to have_http_status(:success)
    end
    
    it 'displays rental items' do
      get business_manager_rentals_path
      expect(response.body).to include(rental.name)
    end
    
    it 'filters by category' do
      get business_manager_rentals_path(category: 'equipment')
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET /manage/rentals/new' do
    it 'returns http success' do
      get new_business_manager_rental_path
      expect(response).to have_http_status(:success)
    end
    
    it 'displays the rental form' do
      get new_business_manager_rental_path
      expect(response.body).to include('New Rental')
    end
  end
  
  describe 'POST /manage/rentals' do
    let(:valid_params) do
      {
        product: {
          name: 'New Rental Item',
          description: 'A great item to rent',
          price: 75.00,
          security_deposit: 150.00,
          rental_quantity_available: 3,
          rental_category: 'equipment',
          active: true
        }
      }
    end
    
    it 'creates a new rental' do
      expect {
        post business_manager_rentals_path, params: valid_params
      }.to change(Product.rentals, :count).by(1)
    end
    
    it 'redirects to show page on success' do
      post business_manager_rentals_path, params: valid_params
      expect(response).to redirect_to(business_manager_rental_path(Product.last))
    end
    
    it 'sets product_type to rental' do
      post business_manager_rentals_path, params: valid_params
      expect(Product.last.product_type).to eq('rental')
    end
  end
  
  describe 'GET /manage/rentals/:id' do
    it 'returns http success' do
      get business_manager_rental_path(rental)
      expect(response).to have_http_status(:success)
    end
    
    it 'displays rental details' do
      get business_manager_rental_path(rental)
      expect(response.body).to include(rental.name)
    end
  end
  
  describe 'GET /manage/rentals/:id/edit' do
    it 'returns http success' do
      get edit_business_manager_rental_path(rental)
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'PATCH /manage/rentals/:id' do
    let(:update_params) do
      {
        product: {
          name: 'Updated Rental Name',
          price: 100.00
        }
      }
    end
    
    it 'updates the rental' do
      patch business_manager_rental_path(rental), params: update_params
      rental.reload
      expect(rental.name).to eq('Updated Rental Name')
      expect(rental.price).to eq(100.00)
    end
    
    it 'redirects to show page' do
      patch business_manager_rental_path(rental), params: update_params
      expect(response).to redirect_to(business_manager_rental_path(rental))
    end
  end
  
  describe 'DELETE /manage/rentals/:id' do
    it 'deletes the rental' do
      expect {
        delete business_manager_rental_path(rental)
      }.to change(Product.rentals, :count).by(-1)
    end
    
    it 'redirects to index' do
      delete business_manager_rental_path(rental)
      expect(response).to redirect_to(business_manager_rentals_path)
    end
    
    context 'with active bookings' do
      before do
        customer = create(:tenant_customer, business: business)
        create(:rental_booking, 
          business: business, 
          product: rental, 
          tenant_customer: customer,
          status: 'deposit_paid'
        )
      end
      
      it 'does not delete the rental' do
        expect {
          delete business_manager_rental_path(rental)
        }.not_to change(Product.rentals, :count)
      end
      
      it 'shows an error message' do
        delete business_manager_rental_path(rental)
        expect(flash[:alert]).to be_present
      end
    end
  end
  
  describe 'GET /manage/rentals/:id/availability' do
    it 'returns availability data' do
      get availability_business_manager_rental_path(rental), as: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_a(Hash)
    end
  end
end

