# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessAccessGuard, type: :service do
  let(:business_a) { create(:business, hostname: 'business-a') }
  let(:business_b) { create(:business, hostname: 'business-b') }
  let(:manager_user) { create(:user, :manager, business: business_a) }
  let(:staff_user) { create(:user, :staff, business: business_a) }
  let(:client_user) { create(:user, :client) }
  let(:session) { { cart: { '1' => 2, '2' => 1 } } }

  describe '#should_block_access?' do
    context 'when user is not present' do
      it 'returns false' do
        guard = BusinessAccessGuard.new(nil, business_a, session)
        expect(guard.should_block_access?).to be false
      end
    end

    context 'when user is a client' do
      it 'returns false (clients can access any business)' do
        guard = BusinessAccessGuard.new(client_user, business_a, session)
        expect(guard.should_block_access?).to be false
      end
    end

    context 'when user is a manager' do
      it 'returns false when accessing their own business' do
        guard = BusinessAccessGuard.new(manager_user, business_a, session)
        expect(guard.should_block_access?).to be false
      end

      it 'returns true when accessing another business' do
        guard = BusinessAccessGuard.new(manager_user, business_b, session)
        expect(guard.should_block_access?).to be true
      end
    end

    context 'when user is staff' do
      it 'returns false when accessing their own business' do
        guard = BusinessAccessGuard.new(staff_user, business_a, session)
        expect(guard.should_block_access?).to be false
      end

      it 'returns true when accessing another business' do
        guard = BusinessAccessGuard.new(staff_user, business_b, session)
        expect(guard.should_block_access?).to be true
      end
    end

    context 'when current_business is nil' do
      it 'returns false for any user' do
        guard = BusinessAccessGuard.new(manager_user, nil, session)
        expect(guard.should_block_access?).to be false
      end
    end

    # Test for edge case - client with business association (legacy data)
    context 'when user is a client but has a business_id (legacy data)' do
      let(:client_with_business) { create(:user, :client, business: nil) }
      
      it 'returns false (clients should never be blocked)' do
        # Simulate legacy data where client somehow has business_id set
        client_with_business.update_column(:business_id, business_a.id)
        guard = BusinessAccessGuard.new(client_with_business, business_b, session)
        expect(guard.should_block_access?).to be false
      end
    end
  end

  describe '#flash_message' do
    context 'when user should be blocked' do
      it 'returns appropriate message for business users' do
        guard = BusinessAccessGuard.new(manager_user, business_b, session)
        expected_message = "You must sign out and proceed as a guest to access this business. Business users can only access their own business's booking and shopping features."
        expect(guard.flash_message).to eq(expected_message)
      end
    end

    context 'when user should not be blocked' do
      it 'returns nil' do
        guard = BusinessAccessGuard.new(client_user, business_a, session)
        expect(guard.flash_message).to be_nil
      end
    end
  end

  describe '#redirect_path' do
    context 'when current_business is present' do
      it 'returns the business root path' do
        guard = BusinessAccessGuard.new(manager_user, business_b, session)
        expect(guard.redirect_path).to eq('/')
      end
    end

    context 'when current_business is nil' do
      it 'returns root path' do
        guard = BusinessAccessGuard.new(manager_user, nil, session)
        expect(guard.redirect_path).to eq('/')
      end
    end
  end

  describe '#clear_cross_business_cart_items!' do
    let(:guard) { BusinessAccessGuard.new(manager_user, business_b, session) }

    context 'when session has cart items' do
      it 'clears the cart from session' do
        expect(session[:cart]).to be_present
        guard.clear_cross_business_cart_items!
        expect(session[:cart]).to be_nil
      end
    end

    context 'when session has no cart' do
      let(:empty_session) { {} }
      let(:guard_with_empty_session) { BusinessAccessGuard.new(manager_user, business_b, empty_session) }

      it 'does not raise error' do
        expect { guard_with_empty_session.clear_cross_business_cart_items! }.not_to raise_error
        expect(empty_session[:cart]).to be_nil
      end
    end
  end

  describe '#log_blocked_access' do
    let(:guard) { BusinessAccessGuard.new(manager_user, business_b, session) }

    it 'logs the blocked access attempt' do
      expect(Rails.logger).to receive(:warn).with(
        "[SECURITY] Business user #{manager_user.id} (#{manager_user.role}) from business #{business_a.id} " \
        "attempted to access business #{business_b.id}. Access blocked."
      )
      
      guard.log_blocked_access
    end

    context 'when current_business is nil' do
      let(:guard_nil_business) { BusinessAccessGuard.new(manager_user, nil, session) }

      it 'logs with nil business id' do
        expect(Rails.logger).to receive(:warn).with(
          "[SECURITY] Business user #{manager_user.id} (#{manager_user.role}) from business #{business_a.id} " \
          "attempted to access business nil. Access blocked."
        )
        
        guard_nil_business.log_blocked_access
      end
    end
  end

  describe 'private methods' do
    describe '#business_user_accessing_different_business?' do
      context 'when user belongs to the current business' do
        it 'returns false' do
          guard = BusinessAccessGuard.new(manager_user, business_a, session)
          expect(guard.send(:business_user_accessing_different_business?)).to be false
        end
      end

      context 'when user belongs to a different business' do
        it 'returns true' do
          guard = BusinessAccessGuard.new(manager_user, business_b, session)
          expect(guard.send(:business_user_accessing_different_business?)).to be true
        end
      end

      context 'when current_business is nil' do
        it 'returns false' do
          guard = BusinessAccessGuard.new(manager_user, nil, session)
          expect(guard.send(:business_user_accessing_different_business?)).to be false
        end
      end

      context 'when user has no business (edge case)' do
        # This shouldn't happen in practice due to validations, but test defensive programming
        let(:business_orphan_user) { build(:user, :manager, business: business_a) }
        
        before do
          # Simulate user losing business association somehow
          business_orphan_user.save(validate: false)
          business_orphan_user.update_column(:business_id, nil)
        end

        it 'returns false to prevent errors' do
          guard = BusinessAccessGuard.new(business_orphan_user, business_b, session)
          expect(guard.send(:business_user_accessing_different_business?)).to be false
        end
      end
    end
  end
end 