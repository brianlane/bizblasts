require 'rails_helper'

RSpec.describe "Subscription Billing and Processing", type: :request do
  let(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let(:product) { create(:product, business: business, subscription_enabled: true, price: 35.00) }
  let(:service) { create(:service, business: business, subscription_enabled: true, price: 60.00) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  
  let!(:product_subscription) do
    create(:customer_subscription, :active, :product_subscription,
           business: business,
           product: product,
           tenant_customer: tenant_customer,
           quantity: 2,
           frequency: 'monthly',
           next_billing_date: Date.current)
  end
  
  let!(:service_subscription) do
    create(:customer_subscription, :active, :service_subscription,
           business: business,
           service: service,
           tenant_customer: tenant_customer,
           quantity: 1,
           frequency: 'weekly',
           next_billing_date: Date.current)
  end

  before do
    ActsAsTenant.current_tenant = business
    
    # Mock mailers only - let individual tests mock services as needed
    allow(SubscriptionMailer).to receive(:payment_succeeded).and_return(double('mailer', deliver_now: true, deliver_later: true))
    allow(SubscriptionMailer).to receive(:payment_failed).and_return(double('mailer', deliver_now: true, deliver_later: true))
    allow(BusinessMailer).to receive(:subscription_order_received).and_return(double('mailer', deliver_now: true, deliver_later: true))
    allow(BusinessMailer).to receive(:subscription_booking_received).and_return(double('mailer', deliver_now: true, deliver_later: true))
  end

  describe "ProcessSubscriptionsJob" do
    it "processes all subscriptions due for billing" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      # Create additional subscriptions with different billing dates
      future_subscription = create(:customer_subscription, :active, :product_subscription,
                                  business: business, 
                                  product: product,
                                  tenant_customer: tenant_customer,
                                  next_billing_date: 1.week.from_now)
      
      past_subscription = create(:customer_subscription, :active, :service_subscription,
                                business: business,
                                service: service, 
                                tenant_customer: tenant_customer,
                                next_billing_date: 1.day.ago)

      # Mock background job execution
      expect {
        ProcessSubscriptionsJob.perform_now
      }.to change { SubscriptionTransaction.count }.by(3) # 2 current + 1 past due

      # Verify transactions were created for due subscriptions
      expect(product_subscription.reload.subscription_transactions.count).to eq(1)
      expect(service_subscription.reload.subscription_transactions.count).to eq(1)
      expect(past_subscription.reload.subscription_transactions.count).to eq(1)
      expect(future_subscription.reload.subscription_transactions.count).to eq(0)
    end

    it "advances billing dates after successful processing" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      # Set billing day to match current billing date to avoid preference override
      product_subscription.update!(billing_day_of_month: product_subscription.next_billing_date.day)
      service_subscription.update!(billing_day_of_month: service_subscription.next_billing_date.day)
      
      original_product_date = product_subscription.next_billing_date
      original_service_date = service_subscription.next_billing_date

      ProcessSubscriptionsJob.perform_now

      product_subscription.reload
      service_subscription.reload

      # Monthly subscription should advance by 1 month
      expect(product_subscription.next_billing_date).to eq(original_product_date.advance(months: 1))
      
      # Weekly subscription should advance by 1 week
      expect(service_subscription.next_billing_date).to eq(original_service_date.advance(weeks: 1))
    end

    it "handles billing failures gracefully" do
      # Mock service failure
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_raise(StandardError, "Payment failed")

      expect {
        ProcessSubscriptionsJob.perform_now
      }.to change { SubscriptionTransaction.failed_payment.count }.by(1)

      # Subscription should remain active but have failed transaction
      product_subscription.reload
      expect(product_subscription.status).to eq('active')
      expect(product_subscription.subscription_transactions.last.status).to eq('failed')
      expect(product_subscription.subscription_transactions.last.transaction_type).to eq('failed_payment')
    end
  end

  describe "RetryFailedSubscriptionsJob" do
    let!(:failed_transaction) do
      transaction = create(:subscription_transaction, :failed, :billing,
                          customer_subscription: product_subscription,
                          business: product_subscription.business,
                          tenant_customer: product_subscription.tenant_customer,
                          amount: product_subscription.subscription_price,
                          created_at: 1.hour.ago)
      # Set up for retry
      transaction.update!(status: :retrying, next_retry_at: 1.minute.ago, retry_count: 1)
      transaction
    end

    it "retries failed subscriptions" do
      # Mock successful retry
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)

      expect {
        RetryFailedSubscriptionsJob.perform_now
      }.to change { failed_transaction.reload.status }.from('retrying').to('completed')
    end

    it "marks subscription as failed after maximum retries" do
      # Simulate max retries reached
      failed_transaction.update!(retry_count: 3)

      RetryFailedSubscriptionsJob.perform_now

      product_subscription.reload
      expect(product_subscription.status).to eq('failed')
      expect(product_subscription.failure_reason).to include('Maximum retry attempts exceeded')
    end
  end

  describe "subscription transaction management" do
    it "creates billing transactions for active subscriptions" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      expect {
        ProcessSubscriptionsJob.perform_now
      }.to change { SubscriptionTransaction.billing.count }.by(2)

      # Verify transaction details
      product_transaction = product_subscription.subscription_transactions.last
      expect(product_transaction.amount).to eq(product_subscription.total_amount)
      expect(product_transaction.transaction_type).to eq('billing')
      expect(product_transaction.status).to eq('completed')
    end

    it "creates payment transactions for successful payments" do
      # Set up stripe subscription ID for the test
      product_subscription.update!(stripe_subscription_id: 'sub_test_123')
      
      # Simulate webhook payment confirmation
      transaction = create(:subscription_transaction, :billing, :completed,
                          customer_subscription: product_subscription,
                          amount: product_subscription.total_amount)

      # Mock webhook handling
      allow(StripeService).to receive(:handle_customer_subscription_payment_succeeded).and_call_original
      
      expect {
        # Simulate stripe webhook call with proper invoice structure
        stripe_invoice = {
          'id' => 'inv_test_123',
          'subscription' => product_subscription.stripe_subscription_id,
          'amount_paid' => (product_subscription.total_amount * 100).to_i,
          'period_end' => 1.month.from_now.to_i
        }
        StripeService.handle_customer_subscription_payment_succeeded(stripe_invoice)
      }.to change { SubscriptionTransaction.billing.count }.by(1)
    end

    it "creates refund transactions for refunds" do
      # Create original payment
      payment_transaction = create(:subscription_transaction, :payment, :completed,
                                  customer_subscription: product_subscription,
                                  amount: product_subscription.total_amount)

      # Process refund
      expect {
        product_subscription.subscription_transactions.create!(
          business: product_subscription.business,
          tenant_customer: product_subscription.tenant_customer,
          transaction_type: :refund,
          amount: -payment_transaction.amount,
          status: :completed,
          processed_date: Time.current,
          stripe_invoice_id: payment_transaction.stripe_invoice_id
        )
      }.to change { SubscriptionTransaction.refund.count }.by(1)
    end
  end

  describe "subscription fulfillment" do
    context "product subscriptions" do
      it "creates orders for product subscriptions" do
        order_service = double('SubscriptionOrderService')
        allow(SubscriptionOrderService).to receive(:new).with(product_subscription).and_return(order_service)
        expect(order_service).to receive(:process_subscription!).and_return(true)

        ProcessSubscriptionsJob.perform_now

        expect(SubscriptionOrderService).to have_received(:new).with(product_subscription)
      end

      it "handles out-of-stock scenarios" do
        # Mock out of stock scenario
        allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(false)
        
        ProcessSubscriptionsJob.perform_now

        # Should still create transaction but mark as failed
        transaction = product_subscription.subscription_transactions.last
        expect(transaction.status).to eq('failed')
        expect(transaction.transaction_type).to eq('billing')
      end
    end

    context "service subscriptions" do
      it "creates bookings for service subscriptions" do
        booking_service = double('SubscriptionBookingService')
        allow(SubscriptionBookingService).to receive(:new).with(service_subscription).and_return(booking_service)
        expect(booking_service).to receive(:process_subscription!).and_return(true)

        ProcessSubscriptionsJob.perform_now

        expect(SubscriptionBookingService).to have_received(:new).with(service_subscription)
      end

      it "handles booking conflicts" do
        # Mock booking conflict scenario
        allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(false)
        
        ProcessSubscriptionsJob.perform_now

        # Should still create transaction but handle gracefully
        transaction = service_subscription.subscription_transactions.last
        expect(transaction).to be_present
      end
    end
  end

  describe "notification sending" do
    it "sends payment successful notifications" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      expect(SubscriptionMailer).to receive(:payment_succeeded).with(product_subscription).and_return(double('mailer', deliver_now: true))
      expect(SubscriptionMailer).to receive(:payment_succeeded).with(service_subscription).and_return(double('mailer', deliver_now: true))

      ProcessSubscriptionsJob.perform_now
    end

    it "sends payment failed notifications" do
      # Mock payment failure for product subscription only
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_raise(StandardError, "Payment failed")
      # Mock successful processing for service subscription
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)

      expect(SubscriptionMailer).to receive(:payment_failed).with(product_subscription).and_return(double('mailer', deliver_now: true))

      ProcessSubscriptionsJob.perform_now
    end

    it "sends business notifications for new orders/bookings" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      expect(BusinessMailer).to receive(:subscription_order_received).and_return(double('mailer', deliver_now: true))
      expect(BusinessMailer).to receive(:subscription_booking_received).and_return(double('mailer', deliver_now: true))

      ProcessSubscriptionsJob.perform_now
    end
  end

  describe "billing cycle management" do
    it "handles different billing frequencies" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      allow_any_instance_of(SubscriptionBookingService).to receive(:process_subscription!).and_return(true)
      
      # Create subscriptions with different frequencies
              weekly_sub = create(:customer_subscription, :active, :product_subscription,
                          business: business, product: product, tenant_customer: tenant_customer,
                          frequency: 'weekly', next_billing_date: Date.current,
                          billing_day_of_month: Date.current.day)
      
      quarterly_sub = create(:customer_subscription, :active, :service_subscription,
                           business: business, service: service, tenant_customer: tenant_customer,
                           frequency: 'quarterly', next_billing_date: Date.current,
                           billing_day_of_month: Date.current.day)

      ProcessSubscriptionsJob.perform_now

      # Verify billing dates advanced correctly
              expect(weekly_sub.reload.next_billing_date).to eq(Date.current.advance(weeks: 1))
      expect(quarterly_sub.reload.next_billing_date).to eq(Date.current.advance(months: 3))
    end

    it "handles billing day of month preference" do
      # Mock successful service processing
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_return(true)
      
      # Set specific billing day
      product_subscription.update!(billing_day_of_month: 15)
      
      # Set next billing date to current date for processing
      product_subscription.update!(next_billing_date: Date.current)

      ProcessSubscriptionsJob.perform_now

      # Next billing should be on the 15th of next month
      expected_date = Date.current.advance(months: 1).beginning_of_month + 14.days
      expect(product_subscription.reload.next_billing_date).to eq(expected_date)
    end
  end

  describe "error handling and recovery" do
    it "handles database transaction failures" do
      # Mock database failure for billing transactions only
      allow_any_instance_of(CustomerSubscription).to receive(:process_billing!).and_raise(ActiveRecord::RecordInvalid, "Database error")

      expect {
        ProcessSubscriptionsJob.perform_now
      }.to change { SubscriptionTransaction.failed_payment.count }.by(2) # Both subscriptions fail

      # Subscriptions should remain unchanged
      expect(product_subscription.reload.status).to eq('active')
      expect(service_subscription.reload.status).to eq('active')
    end

    it "handles external service timeouts" do
      # Mock service timeout
      allow_any_instance_of(SubscriptionOrderService).to receive(:process_subscription!).and_raise(Timeout::Error)

      expect {
        ProcessSubscriptionsJob.perform_now
      }.to change { SubscriptionTransaction.failed_payment.count }.by(1)
    end

    it "continues processing other subscriptions after individual failures" do
      # Mock failure for first subscription only
      allow(SubscriptionOrderService).to receive(:new).with(product_subscription).and_raise(StandardError)
      allow(SubscriptionBookingService).to receive(:new).with(service_subscription).and_return(double('service', process_subscription!: true))

      ProcessSubscriptionsJob.perform_now

      # Service subscription should still be processed
      expect(service_subscription.subscription_transactions.count).to eq(1)
    end
  end
end 