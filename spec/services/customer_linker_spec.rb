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

  describe 'production SMS duplicate scenario' do
    context 'when business has SMS enabled' do
      before { business.update!(sms_enabled: true, tier: 'premium') }

      context 'when user has multiple duplicate customers with different phone formats and SMS opt-in status' do
        let(:user) { create(:user, :client, email: 'user@example.com', phone: '6026866672') }

        # Create the exact production scenario: 3 customers with same phone, different formats
        let!(:customer_8_format) do
          create(:tenant_customer,
            business: business,
            email: 'customer8@example.com',
            phone: '6026866672',           # Original format like Customer 8
            phone_opt_in: false,           # Not opted in
            user_id: nil,
            first_name: 'Customer',
            last_name: 'Eight',
            created_at: 3.days.ago
          )
        end

        let!(:customer_9_format) do
          create(:tenant_customer,
            business: business,
            email: 'customer9@example.com',
            phone: '16026866672',          # Another format like Customer 9
            phone_opt_in: false,           # Not opted in
            user_id: nil,
            first_name: 'Customer',
            last_name: 'Nine',
            created_at: 2.days.ago
          )
        end

        let!(:customer_18_format) do
          create(:tenant_customer,
            business: business,
            email: 'customer18@example.com',
            phone: '+16026866672',         # Normalized format like Customer 18
            phone_opt_in: true,            # SMS OPTED IN - this is the important one!
            phone_opt_in_at: 1.day.ago,
            user_id: nil,
            first_name: 'Customer',
            last_name: 'Eighteen',
            created_at: 1.day.ago
          )
        end

        it 'automatically resolves phone duplicates and preserves SMS opt-in during user linking' do
          # Verify initial state: 3 duplicate customers, only one with SMS opt-in
          expect(business.tenant_customers.count).to eq(3)

          customers_with_phone = [customer_8_format, customer_9_format, customer_18_format]
          sms_opted_customers = customers_with_phone.select(&:phone_opt_in?)
          expect(sms_opted_customers.count).to eq(1)
          expect(sms_opted_customers.first).to eq(customer_18_format)

          # When user links to customer (like during booking flow)
          result_customer = linker.link_user_to_customer(user)

          # Then: CustomerLinker should automatically resolve phone duplicates
          expect(result_customer).to be_persisted
          expect(result_customer.user_id).to eq(user.id)

          # And: Should preserve SMS opt-in status from the best customer (customer_18_format)
          expect(result_customer.phone_opt_in?).to be true
          expect(result_customer.phone_opt_in_at).to be_present

          # And: Phone should be normalized to consistent format
          expect(result_customer.phone).to eq('+16026866672')

          # And: Customer should be able to receive SMS notifications
          expect(result_customer.can_receive_sms?(:booking)).to be true
          expect(result_customer.can_receive_sms?(:payment)).to be true

          # And: Duplicates should be resolved (fewer total customers)
          expect(business.tenant_customers.count).to be < 3

          # And: No other customers should have the same phone number
          remaining_customers = business.tenant_customers.where.not(id: result_customer.id)
          phone_numbers = remaining_customers.pluck(:phone).map { |p| linker.send(:normalize_phone, p) }
          expect(phone_numbers).not_to include('+16026866672')
        end

        it 'preserves complete customer data during phone duplicate resolution' do
          # When user links to customer
          result_customer = linker.link_user_to_customer(user)

          # Then: Should have complete customer information
          expect(result_customer.first_name).to be_present
          expect(result_customer.last_name).to be_present
          expect(result_customer.email).to be_present
          expect(result_customer.phone).to eq('+16026866672')

          # And: Should preserve the best data from merged customers
          # (In this case, preserving the customer with SMS opt-in)
          expect(result_customer.phone_opt_in?).to be true
        end

        it 'handles subsequent calls to link_user_to_customer idempotently' do
          # When user links to customer multiple times (like multiple bookings)
          first_result = linker.link_user_to_customer(user)
          second_result = linker.link_user_to_customer(user)

          # Then: Should return the same customer
          expect(second_result.id).to eq(first_result.id)
          expect(second_result.phone_opt_in?).to be true

          # And: Should not create additional duplicate customers
          expect(business.tenant_customers.count).to eq(1)
        end

        it 'enables end-to-end SMS notification flow' do
          # When user links to customer
          result_customer = linker.link_user_to_customer(user)

          # Then: Complete SMS flow should be possible
          expect(business.can_send_sms?).to be true
          expect(result_customer.can_receive_sms?(:booking)).to be true

          # And: Would allow SMS notifications to be sent
          expect(result_customer.phone_opt_in?).to be true
          expect(result_customer.phone).to be_present
        end

        it 'prevents data integrity issues when canonical customer is linked to different user' do
          # Given: Canonical customer already linked to different user
          other_user = create(:user, :client, email: 'other@example.com', phone: '5551234567')
          customer_18_format.update!(user_id: other_user.id)

          # When: Current user tries to link (should raise error for data integrity)
          expect {
            linker.link_user_to_customer(user)
          }.to raise_error(ArgumentError, /phone number conflicts with existing customer accounts/)

          # Then: Existing user link should be preserved
          customer_18_format.reload
          expect(customer_18_format.user_id).to eq(other_user.id)  # Preserved existing link

          # And: No duplicate phone numbers should exist across different users
          same_phone_customers = business.tenant_customers.where(
            'phone IN (?)',
            ['+16026866672', '16026866672', '6026866672']
          ).where.not(user_id: nil)

          user_ids = same_phone_customers.pluck(:user_id).uniq
          expect(user_ids.count).to eq(1), "Expected only one user with phone +16026866672, but found: #{user_ids}"
          expect(user_ids.first).to eq(other_user.id)
        end


        it 'updates SMS opt-in status when user phone number changes for compliance' do
          # Given: Customer linked to user with SMS opt-in
          result_customer = linker.link_user_to_customer(user)
          expect(result_customer.phone_opt_in?).to be true  # From duplicate resolution

          # When: User's phone number changes to a number without SMS opt-in
          user.update!(phone: '5551112222', phone_opt_in: false, phone_opt_in_at: nil)

          # And: Customer data is synced (like during subsequent booking)
          linker.sync_user_data_to_customer(user, result_customer)

          # Then: Customer's SMS opt-in should be updated for compliance
          result_customer.reload
          expect(result_customer.phone).to eq('5551112222')
          expect(result_customer.phone_opt_in?).to be false  # Updated for compliance
          expect(result_customer.phone_opt_in_at).to be_nil

          # And: Customer should not be able to receive SMS for new number
          expect(result_customer.can_receive_sms?(:booking)).to be false
        end

        it 'preserves SMS opt-in status when user phone number changes to opted-in number' do
          # Given: Customer linked to user without SMS opt-in initially
          user.update!(phone_opt_in: false, phone_opt_in_at: nil)
          result_customer = linker.link_user_to_customer(user)
          expect(result_customer.phone_opt_in?).to be true  # From duplicate resolution

          # When: User's phone number changes to a number WITH SMS opt-in
          new_opt_in_time = 1.hour.ago
          user.update!(phone: '5551112222', phone_opt_in: true, phone_opt_in_at: new_opt_in_time)

          # And: Customer data is synced
          linker.sync_user_data_to_customer(user, result_customer)

          # Then: Customer's SMS opt-in should reflect new number's consent
          result_customer.reload
          expect(result_customer.phone).to eq('5551112222')
          expect(result_customer.phone_opt_in?).to be true
          expect(result_customer.phone_opt_in_at).to be_within(1.second).of(new_opt_in_time)

          # And: Customer should be able to receive SMS
          expect(result_customer.can_receive_sms?(:booking)).to be true
        end
      end
    end
  end
end
