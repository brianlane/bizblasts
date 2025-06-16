# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionOrderService, type: :service do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:product) { create(:product, business: business, price: 50.00, subscription_enabled: true) }
  let(:customer_subscription) do
    create(:customer_subscription, 
           :product_subscription,
           business: business,
           tenant_customer: tenant_customer,
           product: product,
           quantity: 2,
           subscription_price: 95.00)
  end
  
  subject(:service) { described_class.new(customer_subscription) }

  before do
    # Mock Stripe service to avoid external API calls
    allow(StripeService).to receive(:configure_stripe_api_key)
    
    # Mock email delivery
    allow(OrderMailer).to receive_message_chain(:subscription_order_created, :deliver_later)
    allow(BusinessMailer).to receive_message_chain(:subscription_order_received, :deliver_later)
    
    # Mock loyalty service
    allow(SubscriptionLoyaltyService).to receive(:new).and_return(double('loyalty_service', award_subscription_points!: true, check_and_award_milestone_points!: true))
    
    # Default mock for stock service - can be overridden in specific contexts
    # Most tests expect fallback logic, so default to failure
    allow(SubscriptionStockService).to receive(:new).and_return(
      double('stock_service', process_subscription_with_stock_intelligence!: false)
    )
  end

  describe '#initialize' do
    it 'sets the customer subscription' do
      expect(service.customer_subscription).to eq(customer_subscription)
      expect(service.business).to eq(business)
      expect(service.tenant_customer).to eq(tenant_customer)
      expect(service.product).to eq(product)
    end
  end

  describe '#process_subscription!' do
    context 'when subscription is valid for processing' do
      before do
        customer_subscription.update!(status: :active)
      end

      it 'attempts enhanced stock processing first' do
        stock_service = double('stock_service')
        expect(SubscriptionStockService).to receive(:new).with(customer_subscription).and_return(stock_service)
        expect(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(true)
        
        result = service.process_subscription!
        expect(result).to be_truthy
      end

      context 'when enhanced processing succeeds' do
        before do
          stock_service = double('stock_service', process_subscription_with_stock_intelligence!: true)
          allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
        end

        it 'returns the result from enhanced processing' do
          result = service.process_subscription!
          expect(result).to be true
        end

        it 'does not fall back to basic processing' do
          expect(service).not_to receive(:fallback_to_basic_order)
          service.process_subscription!
        end
      end

      context 'when enhanced processing fails' do
        before do
          stock_service = double('stock_service', process_subscription_with_stock_intelligence!: false)
          allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
        end

        it 'falls back to basic order processing' do
          expect(service).to receive(:fallback_to_basic_order).and_call_original
          service.process_subscription!
        end

        it 'creates an order through fallback processing' do
          expect {
            service.process_subscription!
          }.to change(Order, :count).by(1)
        end

        it 'creates line items for the order' do
          expect {
            service.process_subscription!
          }.to change(LineItem, :count).by(1)
        end

        it 'creates an invoice for the order' do
          expect {
            service.process_subscription!
          }.to change(Invoice, :count).by(1)
        end

        it 'awards loyalty points' do
          business.update!(loyalty_program_enabled: true)
          loyalty_service = double('loyalty_service')
          expect(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).and_return(loyalty_service)
          expect(loyalty_service).to receive(:award_subscription_payment_points!)
          
          service.process_subscription!
        end

        it 'advances the billing date' do
          original_date = customer_subscription.next_billing_date
          service.process_subscription!
          
          expect(customer_subscription.reload.next_billing_date).to be > original_date
        end

        it 'sends order confirmation email' do
          expect(OrderMailer).to receive(:subscription_order_created).and_return(double(deliver_later: true))
          service.process_subscription!
        end

        it 'sends business notification email' do
          expect(BusinessMailer).to receive(:subscription_order_received).and_return(double(deliver_later: true))
          service.process_subscription!
        end
      end
    end

    context 'when subscription is not valid for processing' do
      it 'returns false for non-product subscriptions' do
        service_subscription = create(:customer_subscription, :service_subscription)
        service = described_class.new(service_subscription)
        
        expect(service.process_subscription!).to be false
      end

      it 'returns false for inactive subscriptions' do
        customer_subscription.update!(status: :cancelled)
        
        expect(service.process_subscription!).to be false
      end
    end
  end

  describe '#fallback_to_basic_order' do
    before do
      customer_subscription.update!(status: :active)
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'creates an order with correct attributes' do
      service.process_subscription!
      
      order = Order.last
      expect(order.business).to eq(business)
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.status).to eq('paid')
      expect(order.order_type).to eq('product')
      expect(order.total_amount).to eq(customer_subscription.subscription_price)
    end

    it 'creates line items with correct quantities and prices' do
      service.process_subscription!
      
      line_item = LineItem.last
      expect(line_item.product_variant.product).to eq(product)
      expect(line_item.quantity).to eq(customer_subscription.quantity)
      expect(line_item.price).to eq(customer_subscription.subscription_price / customer_subscription.quantity)
      expect(line_item.total_amount).to eq(customer_subscription.subscription_price)
    end

    it 'creates an invoice with correct total' do
      service.process_subscription!
      
      invoice = Invoice.last
      expect(invoice.business).to eq(business)
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.total_amount).to eq(customer_subscription.subscription_price)
      expect(invoice.status).to eq('paid')
    end

    it 'handles product variants correctly' do
      variant = create(:product_variant, product: product, price_modifier: -5.00)
      customer_subscription.update!(
        product_variant_id: variant.id
      )
      
      service.process_subscription!
      
      line_item = LineItem.last
      expect(line_item.product_variant).to eq(variant)
      # For subscription orders, price is based on subscription price, not product price + modifier
      expected_price = customer_subscription.subscription_price / customer_subscription.quantity
      expect(line_item.price).to eq(expected_price)
    end
  end

  describe 'error handling' do
    before do
      customer_subscription.update!(status: :active)
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'handles database errors gracefully' do
      # Mock the Order.create! to raise an error in the fallback logic
      allow(business.orders).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Order.new))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
      
      expect(service.process_subscription!).to be false
    end

    it 'handles Stripe errors gracefully' do
      allow(StripeService).to receive(:configure_stripe_api_key).and_raise(Stripe::StripeError.new('API Error'))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end

    it 'logs errors appropriately' do
      allow(Rails.logger).to receive(:error)
      # Mock the Order.create! to raise an error in the fallback logic
      allow(business.orders).to receive(:create!).and_raise(StandardError.new('Test error'))
      
      service.process_subscription!
      
      expect(Rails.logger).to have_received(:error).with(/SUB_ORDER.*Error processing subscription/)
    end

    it 'rolls back transaction on error' do
      # Mock the Order.create! to raise an error in the fallback logic
      allow(business.orders).to receive(:create!).and_raise(StandardError.new('Test error'))
      
      expect {
        service.process_subscription!
      }.not_to change(Order, :count)
    end
  end

  describe 'loyalty integration' do
    let(:loyalty_service) { double('loyalty_service') }

    before do
      customer_subscription.update!(status: 'active')
      business.update!(loyalty_program_enabled: true)
      allow(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).and_return(loyalty_service)
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'awards loyalty points for successful orders' do
      expect(loyalty_service).to receive(:award_subscription_payment_points!)
      service.process_subscription!
    end

    it 'checks for milestone achievements' do
      # Make the subscription appear to be exactly 1 month old to trigger first_month milestone
      customer_subscription.update!(created_at: 1.month.ago.beginning_of_day)
      allow(loyalty_service).to receive(:award_subscription_payment_points!)
      expect(loyalty_service).to receive(:award_milestone_points!).with('first_month')
      service.process_subscription!
    end

    it 'handles loyalty service errors gracefully' do
      allow(loyalty_service).to receive(:award_subscription_payment_points!).and_raise(StandardError.new('Loyalty error'))
      allow(loyalty_service).to receive(:award_milestone_points!)
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end
  end

  describe 'email notifications' do
    before do
      customer_subscription.update!(status: 'active')
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'sends order confirmation to customer' do
      order_mailer = double('order_mailer', deliver_later: true)
      expect(OrderMailer).to receive(:subscription_order_created).and_return(order_mailer)
      
      service.process_subscription!
    end

    it 'sends business notification' do
      business_mailer = double('business_mailer', deliver_later: true)
      expect(BusinessMailer).to receive(:subscription_order_received).and_return(business_mailer)
      
      service.process_subscription!
    end

    it 'handles email delivery errors gracefully' do
      allow(OrderMailer).to receive(:subscription_order_created).and_raise(StandardError.new('Email error'))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end
  end

  describe 'multi-tenant behavior' do
    let(:other_business) { create(:business) }
    let(:other_subscription) { create(:customer_subscription, :product_subscription, business: other_business) }

    before do
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'processes subscriptions within correct tenant context' do
      ActsAsTenant.with_tenant(business) do
        service.process_subscription!
        
        order = Order.last
        expect(order.business).to eq(business)
      end
    end

    it 'does not interfere with other tenants' do
      ActsAsTenant.with_tenant(other_business) do
        other_service = described_class.new(other_subscription)
        other_service.process_subscription!
      end
      
      ActsAsTenant.with_tenant(business) do
        expect(Order.count).to eq(0)
      end
    end
  end

  describe 'performance considerations' do
    before do
      customer_subscription.update!(status: 'active')
    end

    it 'processes subscription efficiently' do
      # Test that the service completes without timing out
      result = nil
      expect {
        result = service.process_subscription!
      }.not_to raise_error
      expect(result).to be_truthy
    end

    it 'uses database transactions appropriately' do
      # Mock the enhanced stock service to fail so we test the fallback transaction
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
      
      # Expect at least one transaction call (there may be multiple due to database cleaner, etc.)
      expect(ActiveRecord::Base).to receive(:transaction).at_least(:once).and_call_original
      service.process_subscription!
    end
  end

  describe 'integration with subscription billing cycle' do
    before do
      customer_subscription.update!(status: 'active', next_billing_date: Date.current)
      # Mock the enhanced stock service to fail so we test the fallback logic
      stock_service = double('SubscriptionStockService')
      allow(SubscriptionStockService).to receive(:new).and_return(stock_service)
      allow(stock_service).to receive(:process_subscription_with_stock_intelligence!).and_return(false)
    end

    it 'advances monthly billing date correctly' do
      customer_subscription.update!(frequency: 'monthly')
      original_date = customer_subscription.next_billing_date
      
      service.process_subscription!
      
      expect(customer_subscription.reload.next_billing_date).to eq(original_date + 1.month)
    end

    it 'advances weekly billing date correctly' do
      customer_subscription.update!(frequency: 'weekly')
      original_date = customer_subscription.next_billing_date
      
      service.process_subscription!
      
      expect(customer_subscription.reload.next_billing_date).to eq(original_date + 1.week)
    end

    it 'advances quarterly billing date correctly' do
      customer_subscription.update!(frequency: 'quarterly')
      original_date = customer_subscription.next_billing_date
      
      service.process_subscription!
      
      expect(customer_subscription.reload.next_billing_date).to eq(original_date + 3.months)
    end
  end
end 