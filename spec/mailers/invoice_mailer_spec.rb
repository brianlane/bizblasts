# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceMailer, type: :mailer do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:order) { create(:order, tenant_customer: customer, business: business, order_type: :mixed, line_items_count: 2) }

  let(:invoice) do
    Invoice.create!(
      tenant_customer: customer,
      business: business,
      order: order,
      due_date: 3.days.from_now,
      status: :pending
    )
  end

  before do
    ActionMailer::Base.deliveries.clear
  end

  describe '#invoice_created' do
    subject(:mail) { described_class.invoice_created(invoice) }

    it 'renders the subject with invoice number and business name' do
      expect(mail.subject).to include(invoice.invoice_number)
      expect(mail.subject).to include(business.name)
    end

    it 'includes order line items details in the body' do
      order.line_items.each do |item|
        expect(mail.body.encoded).to include(item.product_variant.product.name)
        expect(mail.body.encoded).to include("Quantity: #{item.quantity}")
      end
    end
  end
end 