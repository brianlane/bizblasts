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
  
  
  describe 'database constraints' do
    it 'prevents duplicate customers with same email per business' do
      create(:tenant_customer, business: business, email: 'test@example.com')
      expect {
        create(:tenant_customer, business: business, email: 'test@example.com')
      }.to raise_error(ActiveRecord::RecordInvalid, /Email must be unique within this business/)
    end
  end

  describe 'phone deduplication' do
    describe '#resolve_phone_duplicates' do
      context 'when no customers exist for phone number' do
        it 'returns nil' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result).to be_nil
        end
      end

      context 'when only one customer exists' do
        let!(:customer) { create(:tenant_customer, business: business, phone: '+15551234567') }

        it 'returns the single customer without changes' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result).to eq(customer)
          expect(TenantCustomer.count).to eq(1)
        end
      end

      context 'when multiple customers exist with different phone formats' do
        let!(:customer1) { create(:tenant_customer, business: business, phone: '5551234567', email: 'customer1@example.com', created_at: 2.days.ago) }
        let!(:customer2) { create(:tenant_customer, business: business, phone: '+15551234567', email: 'customer2@example.com', created_at: 1.day.ago) }

        it 'merges duplicates and returns canonical customer' do
          expect {
            result = linker.resolve_phone_duplicates('5551234567')
            expect(result).to be_a(TenantCustomer)
            expect(result.phone).to eq('+15551234567') # Normalized format
          }.to change(TenantCustomer, :count).by(-1)
        end

        it 'selects oldest customer as canonical by default' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result.email).to eq('customer1@example.com') # Older customer
        end
      end

      context 'when duplicate customers have different priorities' do
        let(:user) { create(:user, :client) }
        let!(:guest_customer) { create(:tenant_customer, business: business, phone: '5551234567', user_id: nil, email: 'guest@example.com', created_at: 2.days.ago) }
        let!(:user_customer) { create(:tenant_customer, business: business, phone: '+15551234567', user_id: user.id, email: 'user@example.com', created_at: 1.day.ago) }

        it 'prioritizes user-linked customer over guest customer' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result.email).to eq('user@example.com') # User-linked customer wins
          expect(result.user_id).to eq(user.id)
        end
      end

      context 'when SMS opt-in needs to be preserved' do
        let!(:customer_no_sms) { create(:tenant_customer, business: business, phone: '5551234567', phone_opt_in: false, created_at: 2.days.ago) }
        let!(:customer_with_sms) { create(:tenant_customer, business: business, phone: '+15551234567', phone_opt_in: true, phone_opt_in_at: 1.day.ago) }

        it 'preserves SMS opt-in status in canonical customer' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result.phone_opt_in?).to be true
          expect(result.phone_opt_in_at).to be_present
        end
      end

      context 'when customers have different completeness scores' do
        let!(:minimal_customer) { create(:tenant_customer, business: business, phone: '5551234567', first_name: 'Min', last_name: 'Customer', email: 'sms-temp@temp.bizblasts.com', phone_opt_in: false, created_at: 2.days.ago) }
        let!(:complete_customer) { create(:tenant_customer, business: business, phone: '+15551234567', first_name: 'John', last_name: 'Doe', email: 'john@example.com', phone_opt_in: true, created_at: 1.day.ago) }

        it 'prioritizes more complete customer data' do
          result = linker.resolve_phone_duplicates('5551234567')
          expect(result.first_name).to eq('John')
          expect(result.last_name).to eq('Doe')
          expect(result.email).to eq('john@example.com')
        end
      end
    end

    describe '#resolve_all_phone_duplicates' do
      context 'when no duplicates exist' do
        let!(:customer1) { create(:tenant_customer, business: business, phone: '+15551234567') }
        let!(:customer2) { create(:tenant_customer, business: business, phone: '+15551234568') }

        it 'returns 0 duplicates resolved' do
          result = linker.resolve_all_phone_duplicates
          expect(result).to eq(0)
          expect(TenantCustomer.count).to eq(2)
        end
      end

      context 'when multiple duplicate groups exist' do
        # Group 1: Two customers with same phone
        let!(:group1_customer1) { create(:tenant_customer, business: business, phone: '5551234567') }
        let!(:group1_customer2) { create(:tenant_customer, business: business, phone: '+15551234567') }

        # Group 2: Three customers with same phone
        let!(:group2_customer1) { create(:tenant_customer, business: business, phone: '5559876543') }
        let!(:group2_customer2) { create(:tenant_customer, business: business, phone: '+15559876543') }
        let!(:group2_customer3) { create(:tenant_customer, business: business, phone: '15559876543') }

        it 'resolves all duplicate groups' do
          expect {
            result = linker.resolve_all_phone_duplicates
            expect(result).to eq(3) # 2 duplicates resolved: (2-1) + (3-1)
          }.to change(TenantCustomer, :count).by(-3)
        end

        it 'leaves one canonical customer per phone number' do
          linker.resolve_all_phone_duplicates

          # Check normalized phone numbers
          remaining_phones = TenantCustomer.pluck(:phone).map { |p| linker.send(:normalize_phone, p) }.uniq
          expect(remaining_phones).to contain_exactly('+15551234567', '+15559876543')
        end
      end
    end

    describe 'relationship migration' do
      context 'when customers have associated records' do
        let!(:customer1) { create(:tenant_customer, business: business, phone: '5551234567', created_at: 2.days.ago) }
        let!(:customer2) { create(:tenant_customer, business: business, phone: '+15551234567', created_at: 1.day.ago) }

        let!(:booking1) { create(:booking, tenant_customer: customer1, business: business) }
        let!(:booking2) { create(:booking, tenant_customer: customer2, business: business) }

        it 'migrates all bookings to canonical customer' do
          canonical = linker.resolve_phone_duplicates('5551234567')

          # All bookings should now belong to canonical customer
          expect(Booking.where(tenant_customer: canonical).count).to eq(2)
          expect(Booking.where(tenant_customer_id: customer2.id).count).to eq(0)
        end
      end
    end

    describe 'private helper methods' do
      describe '#normalize_phone' do
        it 'normalizes various phone number formats' do
          expect(linker.send(:normalize_phone, '5551234567')).to eq('+15551234567')
          expect(linker.send(:normalize_phone, '15551234567')).to eq('+15551234567')
          expect(linker.send(:normalize_phone, '+15551234567')).to eq('+15551234567')
          expect(linker.send(:normalize_phone, '(555) 123-4567')).to eq('+15551234567')
        end

        it 'handles blank input' do
          expect(linker.send(:normalize_phone, nil)).to be_nil
          expect(linker.send(:normalize_phone, '')).to be_nil
          expect(linker.send(:normalize_phone, '   ')).to be_nil
        end
      end

      describe '#find_customers_by_phone' do
        let!(:customer1) { create(:tenant_customer, business: business, phone: '5551234567') }
        let!(:customer2) { create(:tenant_customer, business: business, phone: '+15551234567') }
        let!(:customer3) { create(:tenant_customer, business: business, phone: '15551234567') }
        let!(:other_business_customer) { create(:tenant_customer, phone: '+15551234567') } # Different business

        it 'finds all customers with phone number variations within business' do
          customers = linker.send(:find_customers_by_phone, '5551234567')
          expect(customers.count).to eq(3)
          expect(customers).to include(customer1, customer2, customer3)
          expect(customers).not_to include(other_business_customer)
        end
      end

      describe '#select_canonical_customer' do
        let(:user) { create(:user, :client) }

        let!(:guest_old) { create(:tenant_customer, business: business, user_id: nil, created_at: 3.days.ago, first_name: 'Old', last_name: 'Guest') }
        let!(:guest_new) { create(:tenant_customer, business: business, user_id: nil, created_at: 1.day.ago, first_name: 'New', last_name: 'Guest') }
        let!(:user_linked) { create(:tenant_customer, business: business, user_id: user.id, created_at: 2.days.ago, first_name: 'User', last_name: 'Linked') }

        it 'prioritizes user-linked customer over guest customers' do
          customers = [guest_old, guest_new, user_linked]
          canonical = linker.send(:select_canonical_customer, customers)
          expect(canonical).to eq(user_linked)
        end

        it 'prioritizes older customer when no user-linked customers exist' do
          customers = [guest_old, guest_new]
          canonical = linker.send(:select_canonical_customer, customers)
          expect(canonical).to eq(guest_old)
        end
      end
    end
  end
end
