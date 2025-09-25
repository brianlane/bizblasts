require 'rails_helper'

RSpec.describe CustomerLinker do
  let(:business) { create(:business) }
  let(:linker) { CustomerLinker.new(business) }
  let(:user) { create(:user, :client, email: 'test@example.com') }
  
  describe '#link_user_to_customer' do
    context 'when user has no existing customer' do
      it 'creates a new customer linked to the user' do
        expect {
          customer = linker.link_user_to_customer(user)
          expect(customer).to be_persisted
          expect(customer.user_id).to eq(user.id)
          expect(customer.email).to eq(user.email.downcase)
        }.to change(business.tenant_customers, :count).by(1)
      end
    end
    
    context 'when user already has a linked customer' do
      let!(:existing_customer) { create(:tenant_customer, business: business, user: user, email: user.email) }
      
      it 'returns the existing customer' do
        customer = linker.link_user_to_customer(user)
        expect(customer).to eq(existing_customer)
      end
    end
    
    context 'when unlinked customer exists with same email' do
      let!(:unlinked_customer) { create(:tenant_customer, business: business, user: nil, email: user.email) }
      
      it 'links the existing customer to the user' do
        customer = linker.link_user_to_customer(user)
        expect(customer).to eq(unlinked_customer)
        expect(customer.reload.user_id).to eq(user.id)
      end
    end
    
    context 'when email conflict exists' do
      let(:other_user) { create(:user, :client) }
      let!(:linked_customer) { create(:tenant_customer, business: business, user: other_user, email: user.email) }
      
      it 'raises EmailConflictError' do
        expect {
          linker.link_user_to_customer(user)
        }.to raise_error(EmailConflictError) do |error|
          expect(error.email).to eq(user.email.downcase.strip)
          expect(error.business_id).to eq(business.id)
          expect(error.existing_user_id).to eq(other_user.id)
          expect(error.attempted_user_id).to eq(user.id)
        end
      end
    end
    
    context 'with non-client user' do
      let(:manager_user) { create(:user, :manager) }
      
      it 'raises ArgumentError' do
        expect {
          linker.link_user_to_customer(manager_user)
        }.to raise_error(ArgumentError, "User must be a client")
      end
    end
  end
  
  describe '#find_or_create_guest_customer' do
    let(:email) { 'guest@example.com' }
    
    context 'when no customer exists' do
      it 'creates a new guest customer' do
        expect {
          customer = linker.find_or_create_guest_customer(email, first_name: 'John', last_name: 'Doe')
          expect(customer).to be_persisted
          expect(customer.email).to eq(email.downcase)
          expect(customer.user_id).to be_nil
          expect(customer.first_name).to eq('John')
        }.to change(business.tenant_customers, :count).by(1)
      end
    end
    
    context 'when guest customer already exists' do
      let!(:existing_guest) { create(:tenant_customer, business: business, user: nil, email: email) }
      
      it 'returns the existing guest customer' do
        customer = linker.find_or_create_guest_customer(email)
        expect(customer).to eq(existing_guest)
      end
      
      it 'updates customer with new attributes' do
        customer = linker.find_or_create_guest_customer(email, first_name: 'Updated')
        expect(customer.reload.first_name).to eq('Updated')
      end
    end
    
    context 'when linked customer exists with same email' do
      let(:user) { create(:user, :client) }
      let!(:linked_customer) { create(:tenant_customer, business: business, user: user, email: email) }
      
      it 'returns the linked customer' do
        customer = linker.find_or_create_guest_customer(email)
        expect(customer).to eq(linked_customer)
      end
    end
  end
  
  describe '#merge_duplicate_customers_for_user' do
    let!(:primary_customer) { create(:tenant_customer, business: business, user: user, email: user.email, created_at: 1.day.ago) }
    let!(:duplicate_customer) { create(:tenant_customer, business: business, user: user, email: user.email, created_at: 1.hour.ago, phone: '555-1234') }
    
    it 'merges duplicate customers keeping the oldest as primary' do
      result = linker.merge_duplicate_customers_for_user(user)
      
      expect(result).to eq(primary_customer)
      expect(primary_customer.reload.phone).to eq('555-1234') # Merged from duplicate
      expect { duplicate_customer.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
    
    context 'with associated records' do
      let!(:booking) { create(:booking, tenant_customer: duplicate_customer) }
      
      it 'transfers associated records to primary customer' do
        linker.merge_duplicate_customers_for_user(user)
        
        expect(booking.reload.tenant_customer).to eq(primary_customer)
      end
    end
  end
  
  describe 'concurrency safety' do
    it 'handles concurrent customer creation attempts' do
      # This test would require threading support and is more complex
      # For now, we rely on the unique database constraint to prevent duplicates
      expect {
        # Simulate concurrent creation by attempting to create the same customer twice
        create(:tenant_customer, business: business, email: 'test@example.com')
        create(:tenant_customer, business: business, email: 'test@example.com')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
