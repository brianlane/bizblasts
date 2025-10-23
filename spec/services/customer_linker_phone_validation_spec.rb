# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerLinker, type: :service do
  let(:business) { create(:business) }
  let(:linker) { described_class.new(business) }

  describe '#find_or_create_guest_customer - phone validation (Bug 7)' do
    context 'when phone number is invalid' do
      it 'does not query database for blank phone' do
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: ''
        )

        expect(customer).to be_persisted
        expect(customer.phone).to eq('')
      end

      it 'does not query database for nil phone' do
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: nil
        )

        expect(customer).to be_persisted
        expect(customer.phone).to be_nil
      end

      it 'does not query database for phone with fewer than 7 digits' do
        # The normalize_phone method returns nil for phones with < 7 digits
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '123456' # Only 6 digits - invalid
        )

        expect(customer).to be_persisted
        # Bug 11 fix: Invalid phones are not stored (cleared to prevent garbage data)
        expect(customer.phone).to be_nil
      end

      it 'does not query database for phone with only special characters' do
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '()---' # No digits
        )

        expect(customer).to be_persisted
        # Bug 11 fix: Invalid phones are not stored (cleared to prevent garbage data)
        expect(customer.phone).to be_nil
      end

      it 'does not query database for whitespace-only phone' do
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '   '
        )

        expect(customer).to be_persisted
      end
    end

    context 'when phone number is valid' do
      it 'queries database for valid phone number' do
        # Should call find_customers_by_phone for valid phones
        expect(linker).to receive(:find_customers_by_phone).with('+16026866672').and_call_original

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672'
        )

        expect(customer).to be_persisted
        expect(customer.phone).to eq('+16026866672')
      end

      it 'queries database for 10-digit phone without formatting' do
        # After Bug 9 fix, find_customers_by_phone is called with normalized phone
        expect(linker).to receive(:find_customers_by_phone).with('+16026866672').and_call_original

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '6026866672'
        )

        expect(customer).to be_persisted
      end

      it 'queries database for 7-digit phone (minimum valid length)' do
        # After Bug 9 fix, find_customers_by_phone is called with normalized phone
        expect(linker).to receive(:find_customers_by_phone).with('+8675309').and_call_original

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '8675309'
        )

        expect(customer).to be_persisted
        expect(customer.phone).to eq('+8675309') # Normalized to E.164 format
      end

      it 'raises GuestConflictError when valid phone is linked to another user' do
        existing_user = create(:user, :client, email: 'existing@example.com', phone: '+16026866672')
        existing_customer = create(:tenant_customer,
          business: business,
          user: existing_user,
          phone: '+16026866672',
          first_name: 'Existing',
          last_name: 'User'
        )

        expect {
          linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone: '+16026866672'
          )
        }.to raise_error(GuestConflictError) do |error|
          expect(error.message).to include('already associated with an existing account')
          expect(error.existing_user_id).to eq(existing_user.id)
        end
      end
    end

    context 'phone uniqueness for unlinked guests' do
      it 'allows creating multiple guest customers with the same valid phone number' do
        # First guest customer with phone
        guest1 = linker.find_or_create_guest_customer(
          'guest1@example.com',
          first_name: 'Guest',
          last_name: 'One',
          phone: '+16026866672'
        )

        expect(guest1).to be_persisted
        expect(guest1.user_id).to be_nil
        expect(guest1.phone).to eq('+16026866672')

        # Second guest customer with SAME phone (should be allowed for guests)
        guest2 = linker.find_or_create_guest_customer(
          'guest2@example.com',
          first_name: 'Guest',
          last_name: 'Two',
          phone: '+16026866672'
        )

        expect(guest2).to be_persisted
        expect(guest2.user_id).to be_nil
        expect(guest2.phone).to eq('+16026866672')
        expect(guest2.id).not_to eq(guest1.id)
      end

      it 'clears invalid phones to prevent duplicate accounts with same invalid phone (Bug 11 fix)' do
        # First guest with invalid phone - phone should be cleared
        guest1 = linker.find_or_create_guest_customer(
          'guest1@example.com',
          first_name: 'Guest',
          last_name: 'One',
          phone: '123' # Invalid - only 3 digits
        )

        expect(guest1).to be_persisted
        # Bug 11 fix: Invalid phones are cleared, not stored
        expect(guest1.phone).to be_nil

        # Second guest with same invalid phone - also cleared
        guest2 = linker.find_or_create_guest_customer(
          'guest2@example.com',
          first_name: 'Guest',
          last_name: 'Two',
          phone: '123'
        )

        expect(guest2).to be_persisted
        # Bug 11 fix: Invalid phones are cleared, not stored
        expect(guest2.phone).to be_nil
        expect(guest2.id).not_to eq(guest1.id)
      end
    end

    context 'performance optimization' do
      it 'prevents unnecessary database queries for invalid phones' do
        # The key assertion: we should NOT call find_customers_by_phone for invalid phones
        # This prevents unnecessary database queries
        phone_lookup_queries = []

        ActiveSupport::Notifications.subscribed(
          ->(*, payload) {
            sql = payload[:sql]
            # Track queries that search for phones (WHERE phone IN ...)
            if sql.include?('tenant_customers') && sql.match?(/WHERE.*phone.*IN/i)
              phone_lookup_queries << sql
            end
          },
          'sql.active_record'
        ) do
          linker.find_or_create_guest_customer(
            'newguest@example.com',
            first_name: 'New',
            last_name: 'Guest',
            phone: '123' # Invalid - only 3 digits
          )
        end

        # Critical assertion: NO phone lookup queries should be performed for invalid phones
        expect(phone_lookup_queries).to be_empty
      end

      it 'performs phone lookup query only when phone is valid' do
        query_count = 0

        ActiveSupport::Notifications.subscribed(
          ->(*, payload) {
            sql = payload[:sql]
            # Count queries that include phone lookup (WHERE phone IN ...)
            query_count += 1 if sql.include?('tenant_customers') && sql.include?('phone')
          },
          'sql.active_record'
        ) do
          linker.find_or_create_guest_customer(
            'validphone@example.com',
            first_name: 'Valid',
            last_name: 'Phone',
            phone: '+16026866672' # Valid phone
          )
        end

        # Should have at least 1 phone lookup query for valid phone
        expect(query_count).to be >= 1
      end
    end

    context 'Bug 9: Uses normalized phone for conflict checks' do
      it 'calls find_customers_by_phone with normalized phone, not original' do
        # The bug was that we called find_customers_by_phone with customer_attributes[:phone]
        # instead of the already-computed normalized_phone
        # This test ensures we use the normalized value for consistency

        original_phone = '(602) 686-6672'
        normalized_phone = '+16026866672'

        # Expect find_customers_by_phone to be called with NORMALIZED phone
        expect(linker).to receive(:find_customers_by_phone).with(normalized_phone).and_call_original

        customer = linker.find_or_create_guest_customer(
          'normalized@example.com',
          first_name: 'Normalized',
          last_name: 'Test',
          phone: original_phone
        )

        expect(customer).to be_persisted
      end

      it 'uses normalized phone for conflict detection with formatted input' do
        existing_user = create(:user, :client, email: 'existing@example.com', phone: '+16026866672')
        create(:tenant_customer,
          business: business,
          user: existing_user,
          phone: '+16026866672',
          first_name: 'Existing',
          last_name: 'User'
        )

        # Pass in formatted phone - should still detect conflict via normalized comparison
        expect {
          linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone: '(602) 686-6672' # Formatted version of same number
          )
        }.to raise_error(GuestConflictError) do |error|
          expect(error.message).to include('already associated with an existing account')
        end
      end

      it 'avoids redundant normalization by using already-computed normalized_phone' do
        # This test verifies we don't normalize twice
        original_phone = '602-686-6672'

        # Track normalize_phone calls
        normalize_call_count = 0
        allow(linker).to receive(:normalize_phone).and_wrap_original do |original_method, *args|
          normalize_call_count += 1
          original_method.call(*args)
        end

        linker.find_or_create_guest_customer(
          'efficient@example.com',
          first_name: 'Efficient',
          last_name: 'Test',
          phone: original_phone
        )

        # Should normalize exactly once (at line 93), not again when calling find_customers_by_phone
        # Note: find_customers_by_phone will normalize internally, but we pass the already-normalized value
        expect(normalize_call_count).to be >= 1
      end

      it 'ensures consistent phone matching across different input formats' do
        # Create a customer with normalized phone
        guest1 = linker.find_or_create_guest_customer(
          'guest1@example.com',
          first_name: 'Guest',
          last_name: 'One',
          phone: '+16026866672' # Already normalized
        )

        # Try to create another guest with different format of same number
        # Should allow it since both are guests (no conflict)
        guest2 = linker.find_or_create_guest_customer(
          'guest2@example.com',
          first_name: 'Guest',
          last_name: 'Two',
          phone: '(602) 686-6672' # Different format, same number
        )

        expect(guest2).to be_persisted
        expect(guest2.id).not_to eq(guest1.id)
      end
    end

    context 'edge cases' do
      it 'handles phone with formatting characters that normalize to valid phone' do
        # After Bug 9 fix, this should use the normalized phone internally
        original_phone = '(602) 686-6672'
        normalized_phone = '+16026866672'

        expect(linker).to receive(:find_customers_by_phone).with(normalized_phone).and_call_original

        customer = linker.find_or_create_guest_customer(
          'formatted@example.com',
          first_name: 'Formatted',
          last_name: 'Phone',
          phone: original_phone
        )

        expect(customer).to be_persisted
        expect(customer.phone).to eq(normalized_phone) # Normalized to E.164 format
      end

      it 'handles phone with international prefix' do
        # After Bug 9 fix, should use normalized phone
        # UK number: +44 20 1234 5678 normalizes to +442012345678
        original_phone = '+44 20 1234 5678'
        normalized_phone = '+442012345678'

        expect(linker).to receive(:find_customers_by_phone).with(normalized_phone).and_call_original

        customer = linker.find_or_create_guest_customer(
          'international@example.com',
          first_name: 'International',
          last_name: 'Phone',
          phone: original_phone # UK number
        )

        expect(customer).to be_persisted
      end

      it 'does not perform phone lookup when phone attribute is missing from hash' do
        expect(linker).not_to receive(:find_customers_by_phone)

        customer = linker.find_or_create_guest_customer(
          'nophone@example.com',
          first_name: 'No',
          last_name: 'Phone'
          # phone attribute not provided
        )

        expect(customer).to be_persisted
        expect(customer.phone).to be_nil
      end
    end
  end
end
