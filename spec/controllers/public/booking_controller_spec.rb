require 'rails_helper'

RSpec.describe Public::BookingController, type: :controller do
  let(:business) { create(:business) }
  
  before do
    ActsAsTenant.current_tenant = business
    request.host = host_for(business)
  end

  describe 'POST #create' do
    let(:service) { create(:service, business: business, price: 100.00) }
    let(:staff_member) { create(:staff_member, business: business) }
    let(:start_time) { 1.day.from_now }
    
    let(:valid_booking_params) do
      {
        booking: {
          service_id: service.id,
          staff_member_id: staff_member.id,
          start_time: start_time,
          notes: 'Test booking',
          tenant_customer_attributes: {
            first_name: 'John',
            last_name: 'Doe',
            email: 'john.doe@example.com',
            phone: '555-123-4567'
          }
        }
      }
    end

    context 'when guest user creates booking with existing customer email' do
      let!(:existing_customer) { create(:tenant_customer, business: business, email: 'john.doe@example.com', first_name: 'John', last_name: 'Smith', phone: '555-999-8888') }

      it 'finds existing customer instead of creating duplicate' do
        expect {
          post :create, params: valid_booking_params
        }.not_to change(TenantCustomer, :count)
        
        # Should update existing customer with new info
        existing_customer.reload
        expect(existing_customer.full_name).to eq('John Doe') # Updated from form
        expect(existing_customer.phone).to eq('+15551234567') # Updated from form, normalized to E.164
      end

      it 'creates booking with existing customer' do
        expect {
          post :create, params: valid_booking_params
        }.to change(Booking, :count).by(1)
        
        booking = Booking.last
        expect(booking.tenant_customer).to eq(existing_customer)
        expect(booking.service).to eq(service)
      end
    end

    context 'when guest user creates booking with new customer email' do
      it 'creates new customer' do
        expect {
          post :create, params: valid_booking_params
        }.to change(TenantCustomer, :count).by(1)
        
        customer = TenantCustomer.last
        expect(customer.full_name).to eq('John Doe')
        expect(customer.email).to eq('john.doe@example.com')
        expect(customer.phone).to eq('+15551234567') # Normalized to E.164
      end

      it 'creates booking with new customer' do
        expect {
          post :create, params: valid_booking_params
        }.to change(Booking, :count).by(1)
        
        booking = Booking.last
        expect(booking.tenant_customer.email).to eq('john.doe@example.com')
        expect(booking.service).to eq(service)
      end
    end
  end
end 