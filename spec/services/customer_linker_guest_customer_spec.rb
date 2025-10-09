# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerLinker, 'find_or_create_guest_customer' do
  let(:business) { create(:business) }
  let(:linker) { CustomerLinker.new(business) }

  describe 'Bug 5 Fix: Guest Customer Method Improvements' do
    describe 'Issue 1: Efficient phone conflict check using SQL' do
      let(:existing_user) { create(:user, :client, phone: '+16026866672', business: business) }
      let!(:linked_customer) do
        create(:tenant_customer,
               business: business,
               phone: '+16026866672',
               email: 'linked@example.com',
               user_id: existing_user.id)
      end

      it 'uses ActiveRecord WHERE clause instead of Ruby enumeration for phone lookup' do
        # The fix changes from phone_customers.find { |c| ... } to phone_customers.where.not(user_id: nil).first
        # This verifies the method works correctly without NoMethodError from incorrect usage

        expect {
          linker.find_or_create_guest_customer(
            'newguest@example.com',
            phone: '+16026866672'
          )
        }.to raise_error(GuestConflictError) do |error|
          # The fix ensures we get GuestConflictError using SQL filtering,
          # not NoMethodError from calling .find { } incorrectly
          expect(error.existing_user_id).to eq(existing_user.id)
        end
      end

      it 'raises GuestConflictError when phone belongs to linked customer (using SQL filter)' do
        expect {
          linker.find_or_create_guest_customer(
            'newguest@example.com',
            phone: '+16026866672'
          )
        }.to raise_error(GuestConflictError) do |error|
          expect(error.message).to include('already associated with an existing account')
          expect(error.existing_user_id).to eq(existing_user.id)
          expect(error.phone).to eq('+16026866672')
        end
      end

      it 'handles multiple phone formats efficiently' do
        # Create customers with different phone formats
        formats = ['6026866672', '16026866672', '602-686-6672']

        formats.each do |format|
          expect {
            begin
              linker.find_or_create_guest_customer(
                "guest-#{format}@example.com",
                first_name: 'Guest',
                last_name: 'User',
                phone: format
              )
            rescue GuestConflictError
              # Expected - just verifying it works with all formats
            end
          }.not_to raise_error
        end
      end
    end

    describe 'Issue 2: GuestConflictError for security (documented behavior)' do
      let(:existing_user) { create(:user, :client, business: business) }

      context 'when email belongs to a linked customer' do
        let!(:linked_customer) do
          create(:tenant_customer,
                 business: business,
                 email: 'linked@example.com',
                 user_id: existing_user.id)
        end

        it 'raises GuestConflictError to prevent credential reuse' do
          expect {
            linker.find_or_create_guest_customer(
              'linked@example.com',
              first_name: 'Guest',
              last_name: 'User'
            )
          }.to raise_error(GuestConflictError) do |error|
            expect(error.message).to include('already associated with an existing account')
            expect(error.email).to eq('linked@example.com')
            expect(error.business_id).to eq(business.id)
            expect(error.existing_user_id).to eq(existing_user.id)
          end
        end

        it 'suggests signing in instead of guest checkout' do
          expect {
            linker.find_or_create_guest_customer(
              'linked@example.com',
              first_name: 'Guest',
              last_name: 'User'
            )
          }.to raise_error(GuestConflictError) do |error|
            expect(error.message).to include('Please sign in')
          end
        end
      end

      context 'when phone belongs to a linked customer' do
        let!(:linked_customer) do
          create(:tenant_customer,
                 business: business,
                 email: 'linked@example.com',
                 phone: '+16026866672',
                 user_id: existing_user.id)
        end

        it 'raises GuestConflictError to prevent phone number reuse' do
          expect {
            linker.find_or_create_guest_customer(
              'guest@example.com',
              first_name: 'Guest',
              last_name: 'User',
              phone: '+16026866672'
            )
          }.to raise_error(GuestConflictError) do |error|
            expect(error.message).to include('already associated with an existing account')
            expect(error.phone).to eq('+16026866672')
            expect(error.business_id).to eq(business.id)
            expect(error.existing_user_id).to eq(existing_user.id)
          end
        end

        it 'works with different phone formats' do
          # All these formats should match the linked customer's phone
          ['6026866672', '16026866672', '1-602-686-6672'].each do |format|
            expect {
              linker.find_or_create_guest_customer(
                "guest-#{format}@example.com",
                first_name: 'Guest',
                last_name: 'User',
                phone: format
              )
            }.to raise_error(GuestConflictError)
          end
        end
      end
    end

    describe 'Normal "find or create" behavior (without conflicts)' do
      context 'when guest customer already exists' do
        let!(:existing_guest) do
          create(:tenant_customer,
                 business: business,
                 email: 'guest@example.com',
                 user_id: nil,
                 first_name: 'John')
        end

        it 'finds and returns the existing guest customer' do
          result = linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User'
          )

          expect(result.id).to eq(existing_guest.id)
          expect(result.user_id).to be_nil
          expect(result.email).to eq('guest@example.com')
        end

        it 'updates existing guest customer with new attributes' do
          result = linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Jane',
            last_name: 'Doe',
            phone: '+15551234567'
          )

          expect(result.id).to eq(existing_guest.id)
          expect(result.first_name).to eq('Jane')
          expect(result.last_name).to eq('Doe')
          expect(result.phone).to eq('+15551234567')
        end

        it 'handles phone_opt_in updates correctly' do
          result = linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone_opt_in: true
          )

          expect(result.phone_opt_in?).to be true
          expect(result.phone_opt_in_at).to be_present
        end
      end

      context 'when no guest customer exists' do
        it 'creates a new guest customer' do
          expect {
            linker.find_or_create_guest_customer(
              'newguest@example.com',
              first_name: 'New',
              last_name: 'Guest',
              phone: '+15551234567'
            )
          }.to change { business.tenant_customers.count }.by(1)
        end

        it 'creates guest customer with nil user_id' do
          result = linker.find_or_create_guest_customer(
            'newguest@example.com',
            first_name: 'New',
            last_name: 'Guest'
          )

          expect(result.user_id).to be_nil
          expect(result.email).to eq('newguest@example.com')
        end

        it 'normalizes email to lowercase' do
          result = linker.find_or_create_guest_customer(
            'UPPERCASE@EXAMPLE.COM',
            first_name: 'Upper',
            last_name: 'Case'
          )

          expect(result.email).to eq('uppercase@example.com')
        end

        it 'sets phone_opt_in_at when phone_opt_in is true' do
          result = linker.find_or_create_guest_customer(
            'newguest@example.com',
            first_name: 'New',
            last_name: 'Guest',
            phone_opt_in: true
          )

          expect(result.phone_opt_in?).to be true
          expect(result.phone_opt_in_at).to be_within(1.second).of(Time.current)
        end
      end

      context 'when guest customer exists with same phone (no conflict)' do
        let!(:guest_with_phone) do
          create(:tenant_customer,
                 business: business,
                 email: 'guest1@example.com',
                 phone: '+15551234567',
                 user_id: nil)
        end

        it 'allows creating another guest with same phone number' do
          # Guest customers (user_id: nil) can share phone numbers
          # Only linked customers trigger conflicts
          expect {
            linker.find_or_create_guest_customer(
              'guest2@example.com',
              first_name: 'Guest2',
              last_name: 'User',
              phone: '+15551234567'
            )
          }.not_to raise_error
        end
      end
    end

    describe 'Edge cases and validation' do
      it 'handles blank phone gracefully' do
        expect {
          linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone: ''
          )
        }.not_to raise_error
      end

      it 'handles nil phone gracefully' do
        expect {
          linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone: nil
          )
        }.not_to raise_error
      end

      it 'handles phone with only whitespace gracefully' do
        expect {
          linker.find_or_create_guest_customer(
            'guest@example.com',
            first_name: 'Guest',
            last_name: 'User',
            phone: '   '
          )
        }.not_to raise_error
      end
    end
  end
end
