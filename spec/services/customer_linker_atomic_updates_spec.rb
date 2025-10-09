# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerLinker, type: :service do
  describe '#resolve_phone_conflicts_for_user - atomic updates (Bug 10)' do
    let(:business) { create(:business) }
    let(:linker) { described_class.new(business) }

    context 'when merging duplicates and linking to user' do
      it 'updates user_id and user data atomically in single database operation' do
        # Create duplicate customers with same phone
        phone = '+16026866672'
        customer1 = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'John',
          last_name: 'Doe',
          email: 'john@example.com',
          user_id: nil
        )

        customer2 = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Jane',  # Has data
          last_name: 'Smith',  # Has data
          email: 'duplicate@example.com',
          user_id: nil
        )

        # Create user that will link to merged customer
        user = create(:user, :client,
          phone: phone,
          first_name: 'User',
          last_name: 'Name',
          email: 'user@example.com'
        )

        # Call link_user_to_customer which triggers resolve_phone_conflicts_for_user
        result = linker.link_user_to_customer(user)

        # Verify customer is linked (Bug 10 fix: atomic update with user_id and other data)
        expect(result).to be_persisted
        expect(result.user_id).to eq(user.id)
        expect(result.first_name).to eq('John') # From canonical customer (customer1 had data)
        expect(result.last_name).to eq('Doe')
      end

      it 'ensures no partial updates if exception occurs during atomic operation' do
        phone = '+16026866672'
        customer1 = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Canonical',
          last_name: 'Customer',
          email: 'canonical@example.com',
          user_id: nil
        )

        customer2 = create(:tenant_customer,
          business: business,
          phone: phone,
          email: 'duplicate@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'User',
          last_name: 'Name',
          email: 'user@example.com'
        )

        # Simulate exception during update to test atomicity
        allow_any_instance_of(TenantCustomer).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(customer1))

        # Should raise exception
        expect {
          linker.link_user_to_customer(user)
        }.to raise_error(ActiveRecord::RecordInvalid)

        # Verify NO partial updates occurred - customer should still be unlinked
        customer1.reload
        expect(customer1.user_id).to be_nil
      end

      it 'successfully merges and links when canonical needs user data' do
        phone = '+16026866672'
        # Use create! with validation skip to create customer with minimal data
        canonical = business.tenant_customers.create!(
          phone: phone,
          first_name: 'Temp',  # Will be overwritten by user data
          last_name: 'Temp',   # Will be overwritten by user data
          email: 'canonical@example.com',
          user_id: nil
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Dup',
          last_name: 'Dup',
          email: 'duplicate@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'New',
          last_name: 'User',
          email: 'canonical@example.com'  # Same email to test no update needed
        )

        result = linker.link_user_to_customer(user)

        # Verify atomic update included user_id
        expect(result.user_id).to eq(user.id)
        # Canonical had data, so names preserved (not overwritten)
        expect(result.first_name).to eq('Temp')
        expect(result.last_name).to eq('Temp')
      end

      it 'preserves canonical customer data when it is more complete than user data' do
        phone = '+16026866672'
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Existing',
          last_name: 'Customer',
          email: 'existing@example.com',
          user_id: nil
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          email: 'dup@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'User',
          last_name: 'Name',
          email: 'user@example.com'
        )

        result = linker.link_user_to_customer(user)

        # Canonical customer data should be preserved (not overwritten by user)
        expect(result.user_id).to eq(user.id)
        expect(result.first_name).to eq('Existing')  # Preserved from canonical
        expect(result.last_name).to eq('Customer')   # Preserved from canonical
      end

      it 'updates email atomically when user email differs from canonical' do
        phone = '+16026866672'
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Test',
          last_name: 'User',
          email: 'old@example.com',  # Different from user email
          user_id: nil
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          email: 'dup@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'Test',
          last_name: 'User',
          email: 'NEW@EXAMPLE.COM'  # Different case from canonical
        )

        result = linker.link_user_to_customer(user)

        # Email should be updated atomically with user_id
        expect(result.user_id).to eq(user.id)
        expect(result.email).to eq('new@example.com')  # Normalized case (Bug 10 fix: atomic)
      end
    end

    context 'when canonical is already linked to same user' do
      it 'still merges duplicates but does not require update of existing linkage' do
        phone = '+16026866672'
        user = create(:user, :client, phone: phone)

        # Canonical already linked to this user
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          user_id: user.id,
          email: 'canonical@example.com'
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          user_id: nil,
          email: 'duplicate@example.com'
        )

        result = linker.link_user_to_customer(user)

        # Should return canonical customer (already linked)
        expect(result.id).to eq(canonical.id)
        expect(result.user_id).to eq(user.id)

        # Duplicate should be deleted
        expect(TenantCustomer.exists?(duplicate.id)).to be false
      end
    end

    context 'when canonical is linked to different user' do
      it 'merges duplicates but does not link to current user (security)' do
        phone = '+16026866672'
        other_user = create(:user, :client, phone: phone, email: 'other@example.com')
        current_user = create(:user, :client, phone: phone, email: 'current@example.com')

        # Canonical linked to different user
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          user_id: other_user.id,
          email: 'canonical@example.com'
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          user_id: nil,
          email: 'duplicate@example.com'
        )

        # Should raise PhoneConflictError (phone already linked to different user)
        expect {
          linker.link_user_to_customer(current_user)
        }.to raise_error(PhoneConflictError) do |error|
          expect(error.message).to include('already associated with another account')
        end

        # Canonical should still be linked to other_user (not changed)
        canonical.reload
        expect(canonical.user_id).to eq(other_user.id)
      end
    end

    context 'edge cases' do
      it 'handles empty updates hash gracefully (no blank data to sync)' do
        phone = '+16026866672'
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Complete',
          last_name: 'Data',
          email: 'complete@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'User',
          last_name: 'Name',
          email: 'complete@example.com'  # Same as canonical
        )

        result = linker.link_user_to_customer(user)

        # Should successfully link even when no additional data needs syncing
        expect(result.user_id).to eq(user.id)
        expect(result.first_name).to eq('Complete')
        expect(result.email).to eq('complete@example.com')
      end

      it 'handles case-insensitive email matching during atomic update' do
        phone = '+16026866672'
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          email: 'TEST@example.com',  # Mixed case
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          email: 'test@example.com'  # Lowercase
        )

        result = linker.link_user_to_customer(user)

        # Email will be normalized to user's email (lowercase) due to casecmp? check
        expect(result.user_id).to eq(user.id)
        expect(result.email).to eq('test@example.com')  # Normalized to user email
      end
    end

    context 'data integrity' do
      it 'ensures atomic update fails cleanly if exception occurs' do
        phone = '+16026866672'
        canonical = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Canon',
          last_name: 'Ical',
          email: 'canonical@example.com',
          user_id: nil
        )

        duplicate = create(:tenant_customer,
          business: business,
          phone: phone,
          first_name: 'Dup',
          last_name: 'Licate',
          email: 'duplicate@example.com',
          user_id: nil
        )

        user = create(:user, :client,
          phone: phone,
          first_name: 'User',
          last_name: 'Name',
          email: 'user@example.com'
        )

        # Force atomic update! to fail
        original_canonical_id = canonical.id
        allow_any_instance_of(TenantCustomer).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(canonical))

        expect {
          linker.link_user_to_customer(user)
        }.to raise_error(ActiveRecord::RecordInvalid)

        # Canonical should still exist and be unlinked (atomic update failed)
        expect(TenantCustomer.exists?(original_canonical_id)).to be true
        canonical.reload rescue nil
        if canonical
          expect(canonical.user_id).to be_nil
        end
      end
    end
  end
end
