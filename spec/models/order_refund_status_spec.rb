require 'rails_helper'

RSpec.describe Order, type: :model do
  describe '#check_and_update_refund_status!' do
    let(:business) { create(:business) }
    let(:tenant_customer) { create(:tenant_customer, business: business) }
    let(:order) { create(:order, business: business, tenant_customer: tenant_customer, status: :pending_payment) }
    let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, order: order) }

    before do
      # Silence ActionMailer to avoid unrelated log messages
      allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
    end

    context 'when all payments are refunded' do
      before do
        # Create two payments and mark both as refunded
        create(:payment, invoice: invoice, status: :refunded)
        create(:payment, invoice: invoice, status: :refunded)
      end

      it 'updates order status to refunded' do
        aggregate_failures do
          expect { order.check_and_update_refund_status! }
            .to change { order.reload.status }
            .from('pending_payment')
            .to('refunded')
        end
      end

      it 'logs the status update' do
        messages = []
        allow(Rails.logger).to receive(:info) { |msg| messages << msg }
        order.check_and_update_refund_status!
        expect(messages.any? { |msg| msg =~ /Updated order .* status to refunded - all invoice payments refunded/ }).to be true
      end
    end

    context 'when some payments are not refunded' do
      before do
        # Create two payments, one refunded and one completed
        create(:payment, invoice: invoice, status: :refunded)
        create(:payment, invoice: invoice, status: :completed)
      end

      it 'does not update order status' do
        aggregate_failures do
          expect { order.check_and_update_refund_status! }
            .not_to change { order.reload.status }
        end
      end

      it 'logs that the order is not yet refunded' do
        messages = []
        allow(Rails.logger).to receive(:info) { |msg| messages << msg }
        order.check_and_update_refund_status!
        expect(messages.any? { |msg| msg =~ /Order .* not yet refunded - 1 payments still pending refund/ }).to be true
      end
    end

    context 'when no payments exist' do
      it 'does not update order status' do
        aggregate_failures do
          expect { order.check_and_update_refund_status! }
            .not_to change { order.reload.status }
        end
      end
    end

    context 'when order has no invoice' do
      let(:order_without_invoice) { create(:order, business: business, tenant_customer: tenant_customer, status: :pending_payment) }

      it 'does not update order status' do
        aggregate_failures do
          expect { order_without_invoice.check_and_update_refund_status! }
            .not_to change { order_without_invoice.reload.status }
        end
      end
    end
  end
end 