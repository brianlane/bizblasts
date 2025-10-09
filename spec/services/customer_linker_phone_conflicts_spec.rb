# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerLinker, 'phone conflict detection' do
  let(:business) { create(:business) }
  let(:linker) { CustomerLinker.new(business) }

  describe 'Bug Fix: phone_duplicate_resolution_skipped flag' do
    context 'when phone duplicates exist with conflicting user linkage' do
      let(:existing_user) { create(:user, :client, phone: '+16026866672', business: business) }
      let(:new_user) { create(:user, :client, phone: '+16026866672', business: business) }

      let!(:duplicate1) do
        create(:tenant_customer,
               business: business,
               phone: '+16026866672',
               user_id: existing_user.id,
               first_name: 'John',
               email: 'john@example.com')
      end

      let!(:duplicate2) do
        create(:tenant_customer,
               business: business,
               phone: '6026866672', # Different format, same number
               user_id: nil,
               first_name: 'Jane',
               email: 'jane@example.com')
      end

      it 'sets phone_duplicate_resolution_skipped flag when canonical customer is linked to different user' do
        # The canonical customer should be duplicate1 (has user_id)
        # Attempting to link new_user should trigger phone conflict
        expect {
          linker.link_user_to_customer(new_user)
        }.to raise_error(PhoneConflictError) do |error|
          expect(error.message).to include('already associated with another account')
          expect(error.existing_user_id).to eq(existing_user.id)
          expect(error.attempted_user_id).to eq(new_user.id)
        end
      end

      it 'prevents linking via handle_unlinked_customer_by_email when phone conflicts exist' do
        # Create unlinked customer with new_user's email but conflicting phone
        unlinked = create(:tenant_customer,
                         business: business,
                         email: new_user.email,
                         phone: new_user.phone,
                         user_id: nil)

        # Should raise PhoneConflictError due to phone_duplicate_resolution_skipped flag
        expect {
          linker.link_user_to_customer(new_user)
        }.to raise_error(PhoneConflictError)
      end

      it 'prevents creation via check_final_phone_conflicts when phone conflicts exist' do
        # New user with different email but conflicting phone
        new_user_diff_email = create(:user, :client,
                                     phone: '+16026866672',
                                     email: 'different@example.com',
                                     business: business)

        expect {
          linker.link_user_to_customer(new_user_diff_email)
        }.to raise_error(PhoneConflictError) do |error|
          expect(error.existing_user_id).to eq(existing_user.id)
        end
      end
    end

    context 'when phone duplicates exist without user linkage conflicts' do
      let(:user) { create(:user, :client, phone: '+16026866672', business: business) }

      let!(:duplicate1) do
        create(:tenant_customer,
               business: business,
               phone: '+16026866672',
               user_id: nil,
               first_name: 'Guest1')
      end

      let!(:duplicate2) do
        create(:tenant_customer,
               business: business,
               phone: '6026866672',
               user_id: nil,
               first_name: 'Guest2')
      end

      it 'successfully merges duplicates and links to user when no conflict exists' do
        result = linker.link_user_to_customer(user)

        expect(result).to be_a(TenantCustomer)
        expect(result.user_id).to eq(user.id)
        expect(result.phone).to eq('+16026866672') # Normalized format

        # Duplicates should be merged (only 1 customer remains)
        expect(business.tenant_customers.where(phone: ['+16026866672', '6026866672']).count).to eq(1)
      end

      it 'does not set phone_duplicate_resolution_skipped flag when no conflict' do
        # This should succeed without raising PhoneConflictError
        expect {
          linker.link_user_to_customer(user)
        }.not_to raise_error
      end
    end

    context 'when canonical customer is already linked to the SAME user' do
      let(:user) { create(:user, :client, phone: '+16026866672', business: business) }

      let!(:existing_customer) do
        create(:tenant_customer,
               business: business,
               phone: '+16026866672',
               user_id: user.id)
      end

      let!(:duplicate) do
        create(:tenant_customer,
               business: business,
               phone: '6026866672',
               user_id: nil)
      end

      it 'merges duplicates and returns canonical customer without error' do
        result = linker.link_user_to_customer(user)

        expect(result.id).to eq(existing_customer.id)
        expect(result.user_id).to eq(user.id)

        # Duplicate should be merged
        expect(business.tenant_customers.where(phone: ['+16026866672', '6026866672']).count).to eq(1)
      end
    end
  end

  describe 'Bug Prevention: CustomerLinker method signatures' do
    describe 'instance methods' do
      it 'find_customers_by_phone_public takes only phone_number parameter' do
        expect(linker.method(:find_customers_by_phone_public).arity).to eq(1)
      end

      it 'returns Array from find_customers_by_phone_public' do
        result = linker.find_customers_by_phone_public('+16026866672')
        expect(result).to be_an(Array)
      end
    end

    describe 'class methods' do
      it 'find_customers_by_phone_public takes phone_number and business parameters' do
        expect(CustomerLinker.method(:find_customers_by_phone_public).arity).to eq(2)
      end

      it 'find_customers_by_phone_across_all_businesses takes only phone_number parameter' do
        expect(CustomerLinker.method(:find_customers_by_phone_across_all_businesses).arity).to eq(1)
      end

      it 'find_customers_by_phone_global takes phone_number and optional business' do
        # Should accept 1 or 2 parameters (business is optional)
        expect(CustomerLinker.method(:find_customers_by_phone_global).arity).to eq(-2) # -2 means 1 required + 1 optional
      end

      it 'returns Array from class method find_customers_by_phone_public' do
        result = CustomerLinker.find_customers_by_phone_public('+16026866672', business)
        expect(result).to be_an(Array)
      end

      it 'returns Array from find_customers_by_phone_across_all_businesses' do
        result = CustomerLinker.find_customers_by_phone_across_all_businesses('+16026866672')
        expect(result).to be_an(Array)
      end
    end

    describe 'consistency between instance and class methods' do
      let!(:customer) { create(:tenant_customer, business: business, phone: '+16026866672') }

      it 'instance method and class method return same results for business-scoped search' do
        instance_result = linker.find_customers_by_phone_public('+16026866672')
        class_result = CustomerLinker.find_customers_by_phone_public('+16026866672', business)

        expect(instance_result.map(&:id)).to eq(class_result.map(&:id))
      end

      it 'handles multiple phone formats consistently' do
        formats = ['+16026866672', '6026866672', '16026866672', '1602686667']

        formats.each do |format|
          instance_result = linker.find_customers_by_phone_public(format)
          class_result = CustomerLinker.find_customers_by_phone_public(format, business)

          expect(instance_result.map(&:id)).to eq(class_result.map(&:id)),
                 "Mismatch for format: #{format}"
        end
      end
    end
  end
end
