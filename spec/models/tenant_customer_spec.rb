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

  describe 'unsubscribe token generation' do
    let(:business) { create(:business) }
    
    it 'generates a unique unsubscribe token' do
      ActsAsTenant.with_tenant(business) do
        customer = create(:tenant_customer, business: business)
        expect(customer.unsubscribe_token).to be_present
        expect(customer.unsubscribe_token.length).to eq(64) # 32 hex chars = 64 characters
      end
    end
    
    it 'ensures tokens are unique across User and TenantCustomer tables' do
      ActsAsTenant.with_tenant(business) do
        # Create a tenant customer with a specific token
        customer = create(:tenant_customer, business: business)
        original_token = customer.unsubscribe_token
        
        # Create a user and force it to try to use the same token
        user = build(:user, role: :client)
        user.unsubscribe_token = original_token
        
        # The generate_unsubscribe_token method should detect the collision and generate a new token
        user.send(:generate_unsubscribe_token)
        
        expect(user.unsubscribe_token).not_to eq(original_token)
        expect(user.unsubscribe_token).to be_present
      end
    end
    
    it 'regenerates a new unique token' do
      ActsAsTenant.with_tenant(business) do
        customer = create(:tenant_customer, business: business)
        original_token = customer.unsubscribe_token
        
        customer.send(:regenerate_unsubscribe_token)
        
        expect(customer.unsubscribe_token).not_to eq(original_token)
        expect(customer.unsubscribe_token).to be_present
      end
    end
  end

  describe '#can_receive_email?' do
    let(:business) { create(:business) }
    let(:customer) { create(:tenant_customer, business: business) }

    context 'when customer is not unsubscribed' do
      it 'allows transactional emails' do
        expect(customer.can_receive_email?(:transactional)).to be true
      end

      it 'allows marketing emails when not opted out' do
        customer.update!(email_marketing_opt_out: false)
        expect(customer.can_receive_email?(:marketing)).to be true
      end

      it 'blocks marketing emails when opted out' do
        customer.update!(email_marketing_opt_out: true)
        expect(customer.can_receive_email?(:marketing)).to be false
      end

      it 'allows other email types' do
        %i[blog booking order payment customer system subscription].each do |email_type|
          expect(customer.can_receive_email?(email_type)).to be true
        end
      end

      it 'allows unknown email types' do
        expect(customer.can_receive_email?(:unknown_type)).to be true
      end
    end

    context 'when customer is globally unsubscribed' do
      before do
        customer.update!(unsubscribed_at: Time.current)
      end

      it 'still allows transactional emails' do
        expect(customer.can_receive_email?(:transactional)).to be true
      end

      it 'blocks all other email types' do
        %i[marketing blog booking order payment customer system subscription].each do |email_type|
          expect(customer.can_receive_email?(email_type)).to be false
        end
      end
    end

    context 'with string vs symbol parameters' do
      it 'handles both string and symbol parameters' do
        expect(customer.can_receive_email?(:marketing)).to be true
        expect(customer.can_receive_email?('marketing')).to be true
      end
    end
  end
end 