# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RentalBooking Deposit Preauthorization', type: :model do
  let(:business) { create(:business, tier: 'premium', rental_deposit_preauth_enabled: true) }
  let(:product) { create(:product, :rental, business: business, security_deposit: 100.00) }
  let(:customer) { create(:tenant_customer, business: business) }

  let(:rental_booking) do
    create(:rental_booking,
      business: business,
      product: product,
      tenant_customer: customer,
      status: 'pending_deposit',
      security_deposit_amount: 100.00
    )
  end

  describe '#mark_deposit_authorized!' do
    it 'marks deposit as authorized and sets status to deposit_paid' do
      authorization_id = 'pi_test_auth_123'

      expect {
        rental_booking.mark_deposit_authorized!(authorization_id: authorization_id)
      }.to change { rental_booking.reload.status }.from('pending_deposit').to('deposit_paid')
        .and change { rental_booking.deposit_status }.from('deposit_pending').to('deposit_collected')
        .and change { rental_booking.deposit_authorization_id }.from(nil).to(authorization_id)
        .and change { rental_booking.deposit_authorized_at }.from(nil)
    end

    it 'returns false if not in pending_deposit status' do
      rental_booking.update!(status: 'checked_out')

      result = rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_123')

      expect(result).to be false
      expect(rental_booking.deposit_authorization_id).to be_nil
    end

    it 'sends deposit confirmation notification' do
      expect(rental_booking).to receive(:send_deposit_confirmation)

      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_123')
    end
  end

  describe '#capture_deposit!' do
    before do
      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_auth_123')
    end

    it 'captures the preauthorized deposit via StripeService' do
      allow(StripeService).to receive(:capture_rental_deposit_authorization)
        .with(rental_booking)
        .and_return({ success: true })

      expect {
        rental_booking.capture_deposit!
      }.to change { rental_booking.reload.deposit_captured_at }.from(nil)
        .and change { rental_booking.stripe_deposit_payment_intent_id }.from(nil).to('pi_test_auth_123')
    end

    it 'returns true on successful capture' do
      allow(StripeService).to receive(:capture_rental_deposit_authorization)
        .and_return({ success: true })

      expect(rental_booking.capture_deposit!).to be true
    end

    it 'returns false when capture fails' do
      allow(StripeService).to receive(:capture_rental_deposit_authorization)
        .and_return({ success: false, error: 'Card declined' })

      expect(rental_booking.capture_deposit!).to be false
      expect(rental_booking.reload.deposit_captured_at).to be_nil
    end

    it 'returns false if no authorization_id present' do
      rental_booking.update_column(:deposit_authorization_id, nil)

      expect(rental_booking.capture_deposit!).to be false
    end

    it 'returns false if already captured' do
      rental_booking.update_column(:deposit_captured_at, Time.current)

      expect(rental_booking.capture_deposit!).to be false
    end
  end

  describe '#release_deposit_authorization!' do
    before do
      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_auth_123')
    end

    it 'releases the authorization via StripeService' do
      allow(StripeService).to receive(:cancel_rental_deposit_authorization)
        .with(rental_booking)
        .and_return({ success: true })

      expect {
        rental_booking.release_deposit_authorization!
      }.to change { rental_booking.reload.deposit_authorization_released_at }.from(nil)
    end

    it 'returns true on successful release' do
      allow(StripeService).to receive(:cancel_rental_deposit_authorization)
        .and_return({ success: true })

      expect(rental_booking.release_deposit_authorization!).to be true
    end

    it 'returns false when release fails' do
      allow(StripeService).to receive(:cancel_rental_deposit_authorization)
        .and_return({ success: false, error: 'Already captured' })

      expect(rental_booking.release_deposit_authorization!).to be false
      expect(rental_booking.reload.deposit_authorization_released_at).to be_nil
    end

    it 'returns false if no authorization_id present' do
      rental_booking.update_column(:deposit_authorization_id, nil)

      expect(rental_booking.release_deposit_authorization!).to be false
    end

    it 'returns false if already released' do
      rental_booking.update_column(:deposit_authorization_released_at, Time.current)

      expect(rental_booking.release_deposit_authorization!).to be false
    end

    it 'returns false if already captured' do
      rental_booking.update_column(:deposit_captured_at, Time.current)

      expect(rental_booking.release_deposit_authorization!).to be false
    end
  end

  describe '#using_deposit_preauth?' do
    it 'returns true when business has preauth enabled and deposit is authorized' do
      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_123')

      expect(rental_booking.using_deposit_preauth?).to be true
    end

    it 'returns false when business does not have preauth enabled' do
      business.update!(rental_deposit_preauth_enabled: false)
      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_123')

      expect(rental_booking.using_deposit_preauth?).to be false
    end

    it 'returns false when no authorization_id present' do
      expect(rental_booking.using_deposit_preauth?).to be false
    end
  end

  describe '#check_out! with preauth' do
    before do
      # Update start_time to be in the past so checkout is allowed
      rental_booking.update!(start_time: 1.hour.ago)
      rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_auth_123')
      @staff = create(:staff_member, business: business)
    end

    it 'captures the preauthorized deposit before checkout' do
      allow(StripeService).to receive(:capture_rental_deposit_authorization)
        .with(rental_booking)
        .and_return({ success: true })

      expect {
        rental_booking.check_out!(staff_member: @staff)
      }.to change { rental_booking.reload.deposit_captured_at }.from(nil)
        .and change { rental_booking.status }.to('checked_out')
    end

    it 'rolls back checkout if capture fails' do
      allow(StripeService).to receive(:capture_rental_deposit_authorization)
        .and_return({ success: false, error: 'Card declined' })

      result = rental_booking.check_out!(staff_member: @staff)

      expect(result).to be false
      expect(rental_booking.reload.status).to eq('deposit_paid')
      expect(rental_booking.deposit_captured_at).to be_nil
    end

    it 'does not capture if already captured' do
      rental_booking.update_column(:deposit_captured_at, 1.hour.ago)

      expect(StripeService).not_to receive(:capture_rental_deposit_authorization)

      rental_booking.check_out!(staff_member: @staff)

      expect(rental_booking.reload.status).to eq('checked_out')
    end
  end

  describe '#cancel! with preauth' do
    context 'when deposit is preauthorized but not captured' do
      before do
        rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_auth_123')
      end

      it 'releases the authorization' do
        allow(StripeService).to receive(:cancel_rental_deposit_authorization)
          .with(rental_booking)
          .and_return({ success: true })

        expect {
          rental_booking.cancel!(reason: 'Customer request')
        }.to change { rental_booking.reload.deposit_authorization_released_at }.from(nil)
          .and change { rental_booking.status }.to('cancelled')
      end

      it 'sets deposit_refund_amount to 0 (no charge was made)' do
        allow(StripeService).to receive(:cancel_rental_deposit_authorization)
          .and_return({ success: true })

        expect {
          rental_booking.cancel!(reason: 'Customer request')
        }.to change { rental_booking.reload.deposit_refund_amount }.to(0)
      end

      it 'rolls back cancellation if release fails' do
        allow(StripeService).to receive(:cancel_rental_deposit_authorization)
          .and_return({ success: false, error: 'Already captured' })

        expect {
          rental_booking.cancel!(reason: 'Customer request')
        }.not_to change { rental_booking.reload.status }

        expect(rental_booking.status).to eq('deposit_paid')
      end
    end

    context 'when deposit is captured (already charged)' do
      before do
        rental_booking.mark_deposit_authorized!(authorization_id: 'pi_test_auth_123')
        rental_booking.update_columns(
          deposit_captured_at: 1.hour.ago,
          stripe_deposit_payment_intent_id: 'pi_test_auth_123'
        )
      end

      it 'processes a refund instead of releasing authorization' do
        allow(StripeService).to receive(:process_rental_deposit_refund)
          .with(rental_booking: rental_booking)
          .and_return(double(id: 'refund_123'))

        expect(StripeService).not_to receive(:cancel_rental_deposit_authorization)
        expect(StripeService).to receive(:process_rental_deposit_refund)

        rental_booking.cancel!(reason: 'Customer request')

        expect(rental_booking.reload.deposit_refund_amount).to eq(rental_booking.security_deposit_amount)
      end
    end
  end
end
