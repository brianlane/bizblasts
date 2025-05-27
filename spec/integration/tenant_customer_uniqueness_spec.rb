require 'rails_helper'

RSpec.describe "TenantCustomer Email Uniqueness", type: :request do
  let(:business1) { create(:business, subdomain: 'biz1', hostname: 'biz1') }
  let(:business2) { create(:business, subdomain: 'biz2', hostname: 'biz2') }
  let(:service1) { create(:service, business: business1, price: 100.00) }
  let(:service2) { create(:service, business: business2, price: 150.00) }
  let(:staff1) { create(:staff_member, business: business1) }
  let(:staff2) { create(:staff_member, business: business2) }
  
  let(:customer_params) do
    {
      first_name: 'John',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      phone: '555-123-4567'
    }
  end

  describe "booking creation with duplicate emails" do
    context "same email across different businesses" do
      it "allows creating customers with same email in different businesses" do
        # Create customer in business1
        ActsAsTenant.current_tenant = business1
        host! "#{business1.subdomain}.example.com"
        
        post "/booking", params: {
          booking: {
            service_id: service1.id,
            staff_member_id: staff1.id,
            start_time: 1.day.from_now,
            notes: 'Test booking 1',
            tenant_customer_attributes: customer_params
          }
        }
        
        expect(response).to have_http_status(:redirect) # Should redirect to confirmation
        customer1 = business1.tenant_customers.find_by(email: 'john.doe@example.com')
        expect(customer1).to be_present
        expect(customer1.name).to eq('John Doe')
        
        # Create customer with same email in business2
        ActsAsTenant.current_tenant = business2
        host! "#{business2.subdomain}.example.com"
        
        post "/booking", params: {
          booking: {
            service_id: service2.id,
            staff_member_id: staff2.id,
            start_time: 1.day.from_now,
            notes: 'Test booking 2',
            tenant_customer_attributes: customer_params
          }
        }
        
        expect(response).to have_http_status(:redirect) # Should redirect to confirmation
        customer2 = business2.tenant_customers.find_by(email: 'john.doe@example.com')
        expect(customer2).to be_present
        expect(customer2.name).to eq('John Doe')
        
        # Verify they are different customers
        expect(customer1.id).not_to eq(customer2.id)
        expect(customer1.business_id).to eq(business1.id)
        expect(customer2.business_id).to eq(business2.id)
      end
    end
    
    context "same email within same business" do
      it "finds existing customer instead of creating duplicate" do
        ActsAsTenant.current_tenant = business1
        host! "#{business1.subdomain}.example.com"
        
        # Create first booking with customer
        post "/booking", params: {
          booking: {
            service_id: service1.id,
            staff_member_id: staff1.id,
            start_time: 1.day.from_now,
            notes: 'First booking',
            tenant_customer_attributes: customer_params
          }
        }
        
        expect(response).to have_http_status(:redirect)
        expect(business1.tenant_customers.count).to eq(1)
        original_customer = business1.tenant_customers.first
        
        # Create second booking with same email
        updated_params = customer_params.merge(
          first_name: 'Johnny', # Different name
          phone: '555-999-8888'  # Different phone
        )
        
        post "/booking", params: {
          booking: {
            service_id: service1.id,
            staff_member_id: staff1.id,
            start_time: 2.days.from_now,
            notes: 'Second booking',
            tenant_customer_attributes: updated_params
          }
        }
        
        expect(response).to have_http_status(:redirect)
        expect(business1.tenant_customers.count).to eq(1) # Still only one customer
        
        # Verify customer was updated with new info
        original_customer.reload
        expect(original_customer.name).to eq('Johnny Doe') # Updated name
        expect(original_customer.phone).to eq('555-999-8888') # Updated phone
        expect(original_customer.email).to eq('john.doe@example.com') # Same email
      end
    end
  end
end 