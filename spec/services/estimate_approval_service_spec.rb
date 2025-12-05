# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EstimateApprovalService, type: :service do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:service_item) { create(:service, business: business, duration: 60, price: 100) }
  let(:staff_member) { create(:staff_member, business: business) }

  let(:estimate) do
    create(:estimate,
           business: business,
           tenant_customer: customer,
           status: :sent,
           subtotal: 100,
           taxes: 10,
           total: 110,
           required_deposit: 50,
           proposed_start_time: 1.week.from_now,
           proposed_end_time: 1.week.from_now + 1.hour)
  end

  let!(:required_item) do
    create(:estimate_item,
           estimate: estimate,
           service: service_item,
           description: 'Required Service',
           qty: 1,
           cost_rate: 100,
           optional: false)
  end

  let(:signature_data) { 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' }
  let(:signature_name) { 'John Doe' }
  let(:params) do
    {
      signature_data: signature_data,
      signature_name: signature_name,
      selected_optional_items: []
    }
  end

  before do
    ActsAsTenant.current_tenant = business
    ServicesStaffMember.create!(service: service_item, staff_member: staff_member)
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '#call' do
    let(:mock_booking) { create(:booking, business: business, tenant_customer: customer, service: service_item) }
    let(:mock_invoice) { create(:invoice, business: business, tenant_customer: customer, amount: 100, tax_amount: 10, total_amount: 110) }
    let(:mock_checkout_session) do
      double('Stripe::Checkout::Session',
             id: 'cs_test_123',
             payment_intent: 'pi_test_123',
             url: 'https://checkout.stripe.com/pay/cs_test_123')
    end

    let(:deposit_service) { instance_double(ClientDocuments::DepositService) }

    before do
      # Mock external services
      allow(EstimatePdfGenerator).to receive(:new).and_return(double(generate: true))
      allow(EstimateToBookingService).to receive(:new).and_return(double(call: mock_booking))
      allow(mock_booking).to receive(:reload).and_return(mock_booking)
      allow(mock_booking).to receive(:invoice).and_return(mock_invoice)
      allow(ClientDocuments::DepositService).to receive(:new).and_return(deposit_service)
      allow(deposit_service).to receive(:initiate_checkout!).and_return({ session: mock_checkout_session })
    end

    context 'when all validations pass' do
      it 'returns success result' do
        result = described_class.new(estimate, params).call
        expect(result[:success]).to be true
      end

      it 'includes redirect URL in result' do
        result = described_class.new(estimate, params).call
        expect(result[:redirect_url]).to eq('https://checkout.stripe.com/pay/cs_test_123')
      end

      it 'includes invoice in result' do
        result = described_class.new(estimate, params).call
        expect(result[:invoice]).to eq(mock_invoice)
      end

      it 'includes booking in result' do
        result = described_class.new(estimate, params).call
        expect(result[:booking]).to eq(mock_booking)
      end

      it 'saves signature data to estimate' do
        described_class.new(estimate, params).call
        estimate.reload
        expect(estimate.signature_data).to eq(signature_data)
        expect(estimate.signature_name).to eq(signature_name)
        expect(estimate.signed_at).to be_present
      end

      it 'changes estimate status to pending_payment' do
        expect {
          described_class.new(estimate, params).call
        }.to change { estimate.reload.status }.from('sent').to('pending_payment')
      end

      it 'saves checkout session information to estimate' do
        described_class.new(estimate, params).call
        estimate.reload
        expect(estimate.checkout_session_id).to eq('cs_test_123')
        expect(estimate.payment_intent_id).to eq('pi_test_123')
      end

      it 'calls EstimatePdfGenerator to generate PDF' do
        pdf_generator = double('EstimatePdfGenerator')
        expect(EstimatePdfGenerator).to receive(:new).with(estimate).and_return(pdf_generator)
        expect(pdf_generator).to receive(:generate)
        described_class.new(estimate, params).call
      end

      it 'calls EstimateToBookingService to create booking' do
        booking_service = double('EstimateToBookingService')
        expect(EstimateToBookingService).to receive(:new).with(estimate).and_return(booking_service)
        expect(booking_service).to receive(:call).and_return(mock_booking)
        described_class.new(estimate, params).call
      end

      it 'initiates a client document checkout session' do
        expect(ClientDocuments::DepositService).to receive(:new).with(instance_of(ClientDocument)).and_return(deposit_service)
        expect(deposit_service).to receive(:initiate_checkout!).with(
          hash_including(
            success_url: match(/payment_success=true/),
            cancel_url: match(/payment_cancelled=true/)
          )
        ).and_return({ session: mock_checkout_session })

        described_class.new(estimate, params).call
      end
    end

    context 'validation failures' do
      context 'when estimate cannot be approved' do
        it 'returns failure for draft status' do
          estimate.update!(status: :draft)
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('cannot be approved')
        end

        it 'returns failure for approved status' do
          estimate.update!(status: :approved)
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('cannot be approved')
        end

        it 'returns failure for declined status' do
          estimate.update!(status: :declined)
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('cannot be approved')
        end
      end

      context 'when signature is missing' do
        it 'returns failure when signature_data is blank' do
          params[:signature_data] = ''
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('Signature is required')
        end

        it 'returns failure when signature_name is blank' do
          params[:signature_name] = ''
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('Signature is required')
        end

        it 'returns failure when both signature fields are nil' do
          params[:signature_data] = nil
          params[:signature_name] = nil
          result = described_class.new(estimate, params).call

          expect(result[:success]).to be false
          expect(result[:error]).to include('Signature is required')
        end
      end
    end

    context 'optional items selection' do
      let!(:optional_item1) do
        create(:estimate_item,
               estimate: estimate,
               description: 'Optional Item 1',
               qty: 1,
               cost_rate: 50,
               optional: true,
               customer_selected: true,
               customer_declined: false)
      end

      let!(:optional_item2) do
        create(:estimate_item,
               estimate: estimate,
               description: 'Optional Item 2',
               qty: 1,
               cost_rate: 30,
               optional: true,
               customer_selected: true,
               customer_declined: false)
      end

      before do
        estimate.update!(has_optional_items: true)
        estimate.recalculate_totals!
      end

      it 'marks selected optional items as customer_selected' do
        test_params = params.merge(selected_optional_items: [optional_item1.id.to_s])
        described_class.new(estimate, test_params).call

        optional_item1.reload
        expect(optional_item1.customer_selected).to be true
        expect(optional_item1.customer_declined).to be false
      end

      it 'marks non-selected optional items as customer_declined' do
        # Ensure has_optional_items is true right before service call
        estimate.update_column(:has_optional_items, true)

        test_params = params.merge(selected_optional_items: [optional_item1.id.to_s])
        described_class.new(estimate, test_params).call

        optional_item2.reload
        expect(optional_item2.customer_selected).to be false
        expect(optional_item2.customer_declined).to be true
      end

      it 'recalculates totals after optional items selection' do
        test_params = params.merge(selected_optional_items: [optional_item1.id.to_s])

        expect(estimate).to receive(:recalculate_totals!)
        described_class.new(estimate, test_params).call
      end

      it 'handles integer IDs in selected_optional_items' do
        test_params = params.merge(selected_optional_items: [optional_item1.id, optional_item2.id])
        described_class.new(estimate, test_params).call

        optional_item1.reload
        optional_item2.reload

        expect(optional_item1.customer_selected).to be true
        expect(optional_item2.customer_selected).to be true
      end

      it 'marks all optional items as declined when none selected' do
        # Ensure has_optional_items is true right before service call
        estimate.update_column(:has_optional_items, true)

        test_params = params.merge(selected_optional_items: [])
        described_class.new(estimate, test_params).call

        optional_item1.reload
        optional_item2.reload

        expect(optional_item1.customer_declined).to be true
        expect(optional_item2.customer_declined).to be true
      end
    end

    context 'error handling' do
      it 'returns failure when booking creation fails' do
        allow(EstimateToBookingService).to receive(:new).and_return(double(call: nil))

        result = described_class.new(estimate, params).call
        expect(result[:success]).to be false
        expect(result[:error]).to include('Failed to create booking')
      end

      it 'returns failure when invoice is not present' do
        allow(mock_booking).to receive(:invoice).and_return(nil)

        result = described_class.new(estimate, params).call
        expect(result[:success]).to be false
        expect(result[:error]).to include('Failed to create invoice')
      end

      it 'returns failure when Stripe checkout session creation fails' do
        allow(deposit_service).to receive(:initiate_checkout!)
          .and_raise(Stripe::StripeError.new('Card declined'))

        result = described_class.new(estimate, params).call
        expect(result[:success]).to be false
        expect(result[:error]).to include('Payment processing error')
      end

      it 'returns failure when Stripe raises ArgumentError for minimum amount' do
        allow(deposit_service).to receive(:initiate_checkout!)
          .and_raise(ArgumentError.new('Amount must be at least $0.50'))

        result = described_class.new(estimate, params).call
        expect(result[:success]).to be false
        expect(result[:error]).to include('Amount must be at least')
      end

      it 'logs errors when exceptions occur' do
        allow(EstimateToBookingService).to receive(:new).and_raise(StandardError.new('Test error'))

        expect(Rails.logger).to receive(:error).with(/EstimateApprovalService.*Error/)
        expect(Rails.logger).to receive(:error).with(anything)

        described_class.new(estimate, params).call
      end

      it 'returns generic failure message for unexpected errors' do
        allow(EstimateToBookingService).to receive(:new).and_raise(StandardError.new('Unexpected'))

        result = described_class.new(estimate, params).call
        expect(result[:success]).to be false
        expect(result[:error]).to include('An error occurred')
      end
    end

    context 'URL building' do
      it 'builds success URL with estimate token' do
        result = described_class.new(estimate, params).call

        # The service builds URLs internally, verify via Stripe call
        expect(deposit_service).to have_received(:initiate_checkout!).with(
          hash_including(
            success_url: match(/\/estimates\/#{estimate.token}\?payment_success=true/)
          )
        )
      end

      it 'builds cancel URL with estimate token' do
        result = described_class.new(estimate, params).call

        expect(deposit_service).to have_received(:initiate_checkout!).with(
          hash_including(
            cancel_url: match(/\/estimates\/#{estimate.token}\?payment_cancelled=true/)
          )
        )
      end

      it 'uses correct protocol for production' do
        allow(Rails.env).to receive(:production?).and_return(true)

        result = described_class.new(estimate, params).call

        expect(deposit_service).to have_received(:initiate_checkout!).with(
          hash_including(
            success_url: match(/^https:\/\//),
            cancel_url: match(/^https:\/\//)
          )
        )
      end

      it 'uses http protocol for non-production' do
        allow(Rails.env).to receive(:production?).and_return(false)

        result = described_class.new(estimate, params).call

        expect(deposit_service).to have_received(:initiate_checkout!).with(
          hash_including(
            success_url: match(/^http:\/\//),
            cancel_url: match(/^http:\/\//)
          )
        )
      end
    end

    context 'deposit amount handling' do
      it 'uses required_deposit when set' do
        estimate.update!(required_deposit: 75, total: 150)

        result = described_class.new(estimate, params).call

        described_class.new(estimate, params).call
        expect(estimate.reload.client_document.deposit_amount.to_f).to eq(75)
      end

      it 'uses full total when required_deposit is nil' do
        # Update item to have higher cost so total becomes 150
        required_item.update!(cost_rate: 150)
        estimate.recalculate_totals!
        estimate.update!(required_deposit: nil)

        described_class.new(estimate, params).call
        expect(estimate.reload.client_document.deposit_amount.to_f).to eq(estimate.total.to_f)
      end

      it 'uses full total when required_deposit is zero' do
        # Update item to have higher cost so total becomes 150
        required_item.update!(cost_rate: 150)
        estimate.recalculate_totals!
        estimate.update!(required_deposit: 0)

        described_class.new(estimate, params).call
        expect(estimate.reload.client_document.deposit_amount.to_f).to eq(estimate.total.to_f)
      end
    end

    context 'estimate status transitions' do
      it 'works for sent status' do
        estimate.update!(status: :sent)
        result = described_class.new(estimate, params).call

        expect(result[:success]).to be true
        expect(estimate.reload.status).to eq('pending_payment')
      end

      it 'works for viewed status' do
        estimate.update!(status: :viewed)
        result = described_class.new(estimate, params).call

        expect(result[:success]).to be true
        expect(estimate.reload.status).to eq('pending_payment')
      end
    end
  end
end
