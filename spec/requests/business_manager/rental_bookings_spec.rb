# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::RentalBookings', type: :request do
  let!(:business) { create(:business, subdomain: 'rentalbooktest', host_type: 'subdomain') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff_member) { create(:staff_member, business: business, user: manager) }
  let!(:rental) do
    create(:product, 
      business: business, 
      product_type: :rental, 
      name: 'Test Rental',
      price: 50.00,
      security_deposit: 100.00,
      rental_quantity_available: 3
    )
  end
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:booking) do
    # Set the tenant for factory creation
    ActsAsTenant.with_tenant(business) do
      create(:rental_booking,
        business: business,
        product: rental,
        tenant_customer: customer,
        start_time: 1.day.from_now,
        end_time: 3.days.from_now,
        status: 'deposit_paid'
      )
    end
  end
  
  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in manager
    ActsAsTenant.current_tenant = business
  end
  
  after do
    ActsAsTenant.current_tenant = nil
  end
  
  describe 'GET /manage/rental_bookings' do
    it 'returns http success' do
      get business_manager_rental_bookings_path
      expect(response).to have_http_status(:success)
    end
    
    it 'displays bookings' do
      get business_manager_rental_bookings_path
      expect(response.body).to include(booking.booking_number)
    end
    
    it 'filters by status' do
      get business_manager_rental_bookings_path(status: 'deposit_paid')
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET /manage/rental_bookings/:id' do
    it 'returns http success' do
      get business_manager_rental_booking_path(booking)
      expect(response).to have_http_status(:success)
    end
    
    it 'displays booking details' do
      get business_manager_rental_booking_path(booking)
      expect(response.body).to include(booking.booking_number)
      expect(response.body).to include(customer.full_name)
    end
  end
  
  describe 'GET /manage/rental_bookings/new' do
    it 'returns http success' do
      get new_business_manager_rental_booking_path
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'POST /manage/rental_bookings' do
    let(:valid_params) do
      {
        rental_booking: {
          product_id: rental.id,
          tenant_customer_id: customer.id,
          start_time: 5.days.from_now.iso8601,
          end_time: 7.days.from_now.iso8601,
          quantity: 1
        }
      }
    end
    
    it 'creates a new booking' do
      expect {
        post business_manager_rental_bookings_path, params: valid_params
      }.to change(RentalBooking, :count).by(1)
    end
    
    it 'redirects to show page' do
      post business_manager_rental_bookings_path, params: valid_params
      expect(response).to redirect_to(business_manager_rental_booking_path(RentalBooking.last))
    end
  end
  
  describe 'PATCH /manage/rental_bookings/:id/check_out' do
    before do
      booking.update!(start_time: 1.hour.ago)
    end
    
    it 'checks out the rental' do
      patch check_out_business_manager_rental_booking_path(booking), params: { condition_notes: 'Good condition' }
      booking.reload
      expect(booking.status_checked_out?).to be true
      expect(booking.actual_pickup_time).to be_present
    end
    
    it 'redirects to show page' do
      patch check_out_business_manager_rental_booking_path(booking)
      expect(response).to redirect_to(business_manager_rental_booking_path(booking))
    end
  end
  
  describe 'PATCH /manage/rental_bookings/:id/process_return' do
    before do
      booking.update!(status: 'checked_out', actual_pickup_time: 2.days.ago)
    end
    
    it 'processes the return' do
      patch process_return_business_manager_rental_booking_path(booking), params: { 
        condition_rating: 'good',
        return_notes: 'Returned in good condition'
      }
      booking.reload
      expect(booking.status_returned? || booking.status_completed?).to be true
      expect(booking.actual_return_time).to be_present
    end
  end
  
  describe 'PATCH /manage/rental_bookings/:id/cancel' do
    let(:pending_booking) do
      create(:rental_booking,
        business: business,
        product: rental,
        tenant_customer: customer,
        status: 'pending_deposit'
      )
    end
    
    it 'cancels the booking' do
      patch cancel_business_manager_rental_booking_path(pending_booking), params: { 
        cancellation_reason: 'Customer requested' 
      }
      pending_booking.reload
      expect(pending_booking.status_cancelled?).to be true
    end
  end
  
  describe 'GET /manage/rental_bookings/calendar' do
    it 'returns http success' do
      get calendar_business_manager_rental_bookings_path
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET /manage/rental_bookings/overdue' do
    before do
      create(:rental_booking, :overdue,
        business: business,
        product: rental,
        tenant_customer: customer
      )
    end
    
    it 'returns http success' do
      get overdue_business_manager_rental_bookings_path
      expect(response).to have_http_status(:success)
    end
  end
end

