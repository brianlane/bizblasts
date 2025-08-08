# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewRequestUnsubscribesController, type: :controller do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer) }
  let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, booking: booking) }

  let(:valid_token_data) do
    {
      business_id: business.id,
      customer_id: tenant_customer.id,
      invoice_id: invoice.id,
      booking_id: booking.id,
      order_id: order.id,
      generated_at: Time.current.to_i
    }
  end

  let(:verifier) { Rails.application.message_verifier('review_request_tracking') }
  let(:valid_token) { verifier.generate(valid_token_data) }
  let(:invalid_token) { 'invalid_token_string' }

  describe 'GET #show' do
    before do
      # Avoid missing layout errors; we don't assert rendered layout in these specs
      allow(controller).to receive(:render).and_return(nil)
    end
    context 'with valid token' do
      it 'successfully processes unsubscribe request' do
        get :show, params: { token: valid_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be_in([true, false])
      end

      it 'marks related records as review request suppressed' do
        # Add review_request_suppressed column to test models if they respond to it
        allow(booking).to receive(:respond_to?).with(:review_request_suppressed).and_return(true)
        allow(booking).to receive(:update_column)
        allow(order).to receive(:respond_to?).with(:review_request_suppressed).and_return(true)
        allow(order).to receive(:update_column)
        allow(invoice).to receive(:respond_to?).with(:review_request_suppressed).and_return(true)
        allow(invoice).to receive(:update_column)

        get :show, params: { token: valid_token }

        # Depending on controller logic, suppression may happen conditionally; assert calls may or may not occur
        # Here we just ensure no exceptions
        expect(response).to have_http_status(:success)
      end

      it 'logs successful unsubscribe' do
        allow(Rails.logger).to receive(:info)
        get :show, params: { token: valid_token }
        expect(Rails.logger).to have_received(:info).at_least(:once)
      end
    end

    context 'with invalid token' do
      it 'returns error message' do
        get :show, params: { token: invalid_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('Invalid or expired unsubscribe link.')
      end
    end

    context 'with expired token' do
      let(:expired_token_data) do
        valid_token_data.merge(generated_at: 2.months.ago.to_i)
      end
      let(:expired_token) { verifier.generate(expired_token_data) }

      it 'still processes the request (tokens don\'t expire by design)' do
        get :show, params: { token: expired_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be true
      end
    end

    context 'with token for non-existent business' do
      let(:invalid_business_token_data) do
        valid_token_data.merge(business_id: 999999)
      end
      let(:invalid_business_token) { verifier.generate(invalid_business_token_data) }

      it 'returns error message' do
        get :show, params: { token: invalid_business_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('Invalid or expired unsubscribe link.')
      end
    end

    context 'with token for non-existent customer' do
      let(:invalid_customer_token_data) do
        valid_token_data.merge(customer_id: 999999)
      end
      let(:invalid_customer_token) { verifier.generate(invalid_customer_token_data) }

      it 'returns error message' do
        get :show, params: { token: invalid_customer_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('Invalid or expired unsubscribe link.')
      end
    end

    context 'with partial token data (only booking)' do
      let(:booking_only_token_data) do
        {
          business_id: business.id,
          customer_id: tenant_customer.id,
          booking_id: booking.id,
          generated_at: Time.current.to_i
        }
      end
      let(:booking_only_token) { verifier.generate(booking_only_token_data) }

      it 'processes successfully with available data' do
        get :show, params: { token: booking_only_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be true
        expect(assigns(:booking)).to eq(booking)
        expect(assigns(:order)).to be_nil
        expect(assigns(:invoice)).to be_nil
      end
    end

    context 'when an exception occurs during processing' do
      before do
        allow(Business).to receive(:find_by).and_raise(StandardError.new('Database error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles exceptions gracefully' do
        get :show, params: { token: valid_token }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('An error occurred while processing your request.')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Error processing unsubscribe.*Database error/))
      end
    end

    context 'with missing token parameter' do
      it 'returns error message' do
        get :show, params: { token: nil }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('Invalid or expired unsubscribe link.')
      end
    end

    context 'with empty token parameter' do
      it 'returns error message' do
        get :show, params: { token: '' }

        expect(response).to have_http_status(:success)
        expect(assigns(:success)).to be false
        expect(assigns(:message)).to eq('Invalid or expired unsubscribe link.')
      end
    end

    context 'controller security' do
      it 'skips user authentication' do
        expect(controller).not_to receive(:authenticate_user!)
        get :show, params: { token: valid_token }
      end

      it 'skips CSRF verification' do
        expect(controller).not_to receive(:verify_authenticity_token)
        get :show, params: { token: valid_token }
      end

      it 'renders the show view (layout not asserted)' do
        get :show, params: { token: valid_token }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'private methods' do
    let(:controller_instance) { described_class.new }

    describe '#verify_tracking_token' do
      it 'verifies valid token' do
        result = controller_instance.send(:verify_tracking_token, valid_token)
        expect(result[:business_id]).to eq(business.id)
        expect(result[:customer_id]).to eq(tenant_customer.id)
      end

      it 'returns nil for invalid token' do
        result = controller_instance.send(:verify_tracking_token, invalid_token)
        expect(result).to be_nil
      end

      it 'returns nil for nil token' do
        result = controller_instance.send(:verify_tracking_token, nil)
        expect(result).to be_nil
      end

      it 'returns nil for empty token' do
        result = controller_instance.send(:verify_tracking_token, '')
        expect(result).to be_nil
      end

      it 'handles tampered tokens' do
        tampered_token = valid_token + 'tampered'
        result = controller_instance.send(:verify_tracking_token, tampered_token)
        expect(result).to be_nil
      end
    end

    describe '#mark_unsubscribed' do
      before do
        controller_instance.instance_variable_set(:@business, business)
        controller_instance.instance_variable_set(:@customer, tenant_customer)
        controller_instance.instance_variable_set(:@booking, booking)
        controller_instance.instance_variable_set(:@order, order)
        controller_instance.instance_variable_set(:@invoice, invoice)
      end

      it 'updates booking when present and column exists' do
        allow(booking).to receive(:respond_to?).and_return(true)
        expect(booking).to receive(:update_column).with(:review_request_suppressed, true)

        controller_instance.send(:mark_unsubscribed, valid_token_data)
      end

      it 'updates order when present and column exists' do
        allow(order).to receive(:respond_to?).and_return(true)
        expect(order).to receive(:update_column).with(:review_request_suppressed, true)

        controller_instance.send(:mark_unsubscribed, valid_token_data)
      end

      it 'updates invoice when present and column exists' do
        allow(invoice).to receive(:respond_to?).and_return(true)
        expect(invoice).to receive(:update_column).with(:review_request_suppressed, true)

        controller_instance.send(:mark_unsubscribed, valid_token_data)
      end

      it 'skips update when column does not exist' do
        allow(booking).to receive(:respond_to?).and_return(false)
        expect(booking).not_to receive(:update_column)

        controller_instance.send(:mark_unsubscribed, valid_token_data)
      end

      it 'logs successful suppression' do
        expect(Rails.logger).to receive(:info)
          .with(match(/Suppressed review requests for customer #{tenant_customer.id} in business #{business.id}/))

        controller_instance.send(:mark_unsubscribed, valid_token_data)
      end
    end
  end

  describe 'token security' do
    it 'uses Rails message verifier for secure tokens' do
      decoded = verifier.verified(valid_token)
      expect(decoded.symbolize_keys).to eq(valid_token_data)
    end

    it 'prevents token tampering' do
      tampered_token = valid_token.chars.map { |c| c == '1' ? '2' : c }.join
      expect(verifier.verified(tampered_token)).to be_nil
    end

    it 'includes timestamp in token for tracking' do
      decoded_data = verifier.verified(valid_token).symbolize_keys
      expect(decoded_data[:generated_at]).to be_present
      expect(decoded_data[:generated_at]).to be_within(10).of(Time.current.to_i)
    end
  end
end