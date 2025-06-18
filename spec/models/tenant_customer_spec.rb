# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantCustomer, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business).required }
    it { is_expected.to have_many(:bookings) }
  end

  describe 'validations' do
    it 'validates presence of first_name' do
      customer = TenantCustomer.new(last_name: 'Smith', email: 'test@example.com', phone: '555-123-4567')
      expect(customer).not_to be_valid
      expect(customer.errors[:first_name]).to include("can't be blank")
    end
    
    it 'validates presence of last_name' do
      customer = TenantCustomer.new(first_name: 'John', email: 'test@example.com', phone: '555-123-4567')
      expect(customer).not_to be_valid
      expect(customer.errors[:last_name]).to include("can't be blank")
    end
    
    it 'validates uniqueness of email scoped to business_id' do
      # Use factory to create a valid business
      business = create(:business) 
      ActsAsTenant.with_tenant(business) do
        create(:tenant_customer, email: "test@example.com", business: business)
        customer2 = build(:tenant_customer, email: "test@example.com", business: business)
        expect(customer2).not_to be_valid
        expect(customer2.errors[:email]).to include("must be unique within this business")
      end
    end
    
    it 'allows duplicate emails across different businesses' do
      # Use factories for both businesses
      business1 = create(:business) 
      business2 = create(:business) 

      ActsAsTenant.with_tenant(business1) do
        create(:tenant_customer, email: "duplicate@example.com", business: business1)
      end

      ActsAsTenant.with_tenant(business2) do
        customer_in_biz2 = build(:tenant_customer, email: "duplicate@example.com", business: business2)
        expect(customer_in_biz2).to be_valid
      end
    end

    it 'validates format of email' do
      customer = build(:tenant_customer, email: 'invalid_email')
      expect(customer).not_to be_valid
      expect(customer.errors[:email]).to include('is invalid')
    end

    it 'allows blank phone' do
      customer = build(:tenant_customer, phone: nil)
      customer.validate
      expect(customer.errors[:phone]).to be_empty
    end
  end
  
  describe '#full_name' do
    it 'returns first and last name joined' do
      customer = build(:tenant_customer, first_name: 'John', last_name: 'Smith')
      expect(customer.full_name).to eq('John Smith')
    end
    
    it 'returns email if names are blank' do
      customer = build(:tenant_customer, first_name: '', last_name: '', email: 'test@example.com')
      expect(customer.full_name).to eq('test@example.com')
    end
  end
end 