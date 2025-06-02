# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailCollectionBuilder, type: :service do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
  let(:service) { create(:service, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:builder) { EmailCollectionBuilder.new }

  describe 'initialization' do
    it 'creates an empty builder' do
      expect(builder.count).to eq(0)
    end
  end

  describe '#add_email' do
    it 'adds a simple email specification' do
      result = builder.add_email(BusinessMailer, :new_order_notification, [order])

      expect(result).to eq(builder) # Returns self for chaining
      expect(builder.count).to eq(1)
    end

    it 'creates valid EmailSpecification objects' do
      builder.add_email(BusinessMailer, :new_order_notification, [order])
      specs = builder.build

      expect(specs.length).to eq(1)
      expect(specs.first).to be_a(EmailSpecification)
      expect(specs.first.mailer_class).to eq(BusinessMailer)
      expect(specs.first.method_name).to eq(:new_order_notification)
      expect(specs.first.arguments).to eq([order])
      expect(specs.first.condition).to be_nil
    end

    it 'handles multiple emails' do
      builder
        .add_email(BusinessMailer, :new_order_notification, [order])
        .add_email(InvoiceMailer, :invoice_created, [order.invoice])

      expect(builder.count).to eq(2)
    end
  end

  describe '#add_conditional_email' do
    it 'adds a conditional email specification' do
      condition = -> { true }
      result = builder.add_conditional_email(
        mailer_class: BusinessMailer,
        method_name: :new_customer_notification,
        args: [tenant_customer],
        condition: condition
      )

      expect(result).to eq(builder)
      expect(builder.count).to eq(1)
    end

    it 'creates valid conditional EmailSpecification objects' do
      condition = -> { true }
      builder.add_conditional_email(
        mailer_class: BusinessMailer,
        method_name: :new_customer_notification,
        args: [tenant_customer],
        condition: condition
      )
      specs = builder.build

      expect(specs.length).to eq(1)
      expect(specs.first).to be_a(EmailSpecification)
      expect(specs.first.condition).to eq(condition)
    end
  end

  describe '#add_order_emails' do
    context 'with basic order' do
      it 'adds business order notification email' do
        builder.add_order_emails(order)
        specs = builder.build

        # Should have at least the order notification
        order_spec = specs.find { |s| s.method_name == :new_order_notification }
        expect(order_spec).to be_present
        expect(order_spec.mailer_class).to eq(BusinessMailer)
        expect(order_spec.arguments).to eq([order])
      end
    end

    context 'with newly created customer' do
      let(:new_customer) { create(:tenant_customer, business: business, created_at: 5.seconds.ago) }
      let(:order_with_new_customer) { create(:order, business: business, tenant_customer: new_customer) }

      it 'adds conditional new customer notification' do
        builder.add_order_emails(order_with_new_customer)
        specs = builder.build

        # Should have customer notification with condition
        customer_spec = specs.find { |s| s.method_name == :new_customer_notification }
        expect(customer_spec).to be_present
        expect(customer_spec.condition).to be_present
      end
    end

    context 'with existing invoice' do
      before do
        # Create an invoice for the order
        create(:invoice, order: order, tenant_customer: tenant_customer, business: business)
      end

      it 'adds invoice creation email' do
        builder.add_order_emails(order)
        specs = builder.build

        # Should have invoice email
        invoice_spec = specs.find { |s| s.method_name == :invoice_created }
        expect(invoice_spec).to be_present
        expect(invoice_spec.mailer_class).to eq(InvoiceMailer)
        expect(invoice_spec.arguments).to eq([order.invoice])
      end
    end

    it 'returns self for chaining' do
      result = builder.add_order_emails(order)
      expect(result).to eq(builder)
    end
  end

  describe '#add_booking_emails' do
    let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member) }

    context 'with basic booking' do
      it 'adds business booking notification email' do
        builder.add_booking_emails(booking)
        specs = builder.build

        # Should have at least the booking notification
        booking_spec = specs.find { |s| s.method_name == :new_booking_notification }
        expect(booking_spec).to be_present
        expect(booking_spec.mailer_class).to eq(BusinessMailer)
        expect(booking_spec.arguments).to eq([booking])
      end
    end

    context 'with newly created customer' do
      let(:new_customer) { create(:tenant_customer, business: business, created_at: 5.seconds.ago) }
      let(:booking_with_new_customer) { create(:booking, business: business, tenant_customer: new_customer, service: service, staff_member: staff_member) }

      it 'adds conditional new customer notification' do
        builder.add_booking_emails(booking_with_new_customer)
        specs = builder.build

        # Should have customer notification with condition
        customer_spec = specs.find { |s| s.method_name == :new_customer_notification }
        expect(customer_spec).to be_present
        expect(customer_spec.condition).to be_present
      end
    end

    context 'with existing invoice' do
      before do
        # Create an invoice for the booking
        create(:invoice, booking: booking, tenant_customer: tenant_customer, business: business)
      end

      it 'adds invoice creation email' do
        builder.add_booking_emails(booking)
        specs = builder.build

        # Should have invoice email
        invoice_spec = specs.find { |s| s.method_name == :invoice_created }
        expect(invoice_spec).to be_present
        expect(invoice_spec.arguments).to eq([booking.invoice])
      end
    end

    it 'returns self for chaining' do
      result = builder.add_booking_emails(booking)
      expect(result).to eq(builder)
    end
  end

  describe '#build' do
    it 'returns a frozen array of specifications' do
      builder.add_email(BusinessMailer, :new_order_notification, [order])
      specs = builder.build

      expect(specs).to be_frozen
      expect(specs).to be_an(Array)
      expect(specs.length).to eq(1)
    end

    it 'returns empty array when no emails added' do
      specs = builder.build
      expect(specs).to eq([])
      expect(specs).to be_frozen
    end

    it 'can be called multiple times' do
      builder.add_email(BusinessMailer, :new_order_notification, [order])
      
      specs1 = builder.build
      specs2 = builder.build

      expect(specs1).to eq(specs2)
      expect(specs1.object_id).not_to eq(specs2.object_id) # Different objects
    end
  end

  describe '#count' do
    it 'returns the number of specifications' do
      expect(builder.count).to eq(0)
      
      builder.add_email(BusinessMailer, :new_order_notification, [order])
      expect(builder.count).to eq(1)
      
      builder.add_email(InvoiceMailer, :invoice_created, [order.invoice])
      expect(builder.count).to eq(2)
    end
  end

  describe '#clear' do
    it 'removes all specifications and returns self' do
      builder
        .add_email(BusinessMailer, :new_order_notification, [order])
        .add_email(InvoiceMailer, :invoice_created, [order.invoice])

      expect(builder.count).to eq(2)

      result = builder.clear
      expect(result).to eq(builder)
      expect(builder.count).to eq(0)
    end
  end

  describe 'fluent interface' do
    it 'allows method chaining' do
      specs = builder
        .add_email(BusinessMailer, :new_order_notification, [order])
        .add_conditional_email(
          mailer_class: BusinessMailer,
          method_name: :new_customer_notification,
          args: [tenant_customer],
          condition: -> { true }
        )
        .build

      expect(specs.length).to eq(2)
    end

    it 'supports complex chaining with order helpers' do
      specs = builder
        .add_order_emails(order)
        .add_email(BusinessMailer, :payment_received_notification, [order])
        .build

      expect(specs.count).to be >= 2 # At least order notification + payment notification
    end
  end

  describe 'customer_newly_created? private method' do
    it 'identifies newly created customers' do
      new_customer = create(:tenant_customer, business: business, created_at: 5.seconds.ago)
      old_customer = create(:tenant_customer, business: business, created_at: 1.hour.ago)

      # We test this indirectly through the add_order_emails method
      builder_new = EmailCollectionBuilder.new.add_order_emails(create(:order, business: business, tenant_customer: new_customer))
      builder_old = EmailCollectionBuilder.new.add_order_emails(create(:order, business: business, tenant_customer: old_customer))

      new_specs = builder_new.build
      old_specs = builder_old.build

      # New customer should have a conditional customer notification
      new_customer_spec = new_specs.find { |s| s.method_name == :new_customer_notification }
      old_customer_spec = old_specs.find { |s| s.method_name == :new_customer_notification }

      expect(new_customer_spec).to be_present
      expect(old_customer_spec).to be_present # Both should be present but with different conditions
    end
  end
end 