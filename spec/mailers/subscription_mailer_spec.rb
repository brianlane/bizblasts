# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe SubscriptionMailer, type: :mailer do
  let(:business) { create(:business, name: 'Test Business', email: 'business@test.com') }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: 'customer@test.com', first_name: 'John', last_name: 'Doe') }
  let(:product) { create(:product, business: business, name: 'Test Product', price: 35.00, subscription_enabled: true) }
  let(:service) { create(:service, business: business, name: 'Test Service', price: 60.00, subscription_enabled: true) }

  let(:product_subscription) do
    create(:customer_subscription, :product_subscription, :active,
           business: business,
           tenant_customer: tenant_customer,
           product: product,
           quantity: 2,
           frequency: 'monthly',
           subscription_price: 15.75) # 15.75 * 2 = 31.50 total
  end

  let(:service_subscription) do
    create(:customer_subscription, :service_subscription, :active,
           business: business,
           tenant_customer: tenant_customer,
           service: service,
           quantity: 1,
           frequency: 'weekly',
           subscription_price: 54.00) # 54.00 * 1 = 54.00 total
  end

  before do
    ActsAsTenant.current_tenant = business
    ActionMailer::Base.deliveries.clear
  end

  describe '#signup_confirmation' do
    it 'sends confirmation email for product subscription' do
      mail = SubscriptionMailer.signup_confirmation(product_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Subscription Confirmed')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(product.name)
      expect(mail.body.encoded).to include('$15.75')
    end

    it 'sends confirmation email for service subscription' do
      mail = SubscriptionMailer.signup_confirmation(service_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Subscription Confirmed')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include('$54.0')
    end

    it 'includes business information in confirmation email' do
      mail = SubscriptionMailer.signup_confirmation(product_subscription)

      expect(mail.body.encoded).to include(business.name)
      expect(mail.from).to include(business.email)
    end
  end

  describe '#payment_succeeded' do
    let(:successful_transaction) do
      create(:subscription_transaction, :completed,
             customer_subscription: product_subscription,
             amount: product_subscription.subscription_price,
             processed_date: Date.current)
    end

    before do
      successful_transaction # Create the transaction
    end

    it 'sends payment successful email' do
      mail = SubscriptionMailer.payment_succeeded(product_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Payment Processed')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(product.name)
      expect(mail.body.encoded).to include('processed successfully')
    end

    it 'includes transaction details in payment email' do
      mail = SubscriptionMailer.payment_succeeded(product_subscription)

      expect(mail.body.encoded).to include('$15.75')
      expect(mail.body.encoded).to include('Next Billing Date')
    end

    it 'includes next billing date in payment email' do
      product_subscription.update!(next_billing_date: 1.month.from_now)
      mail = SubscriptionMailer.payment_succeeded(product_subscription)

      expect(mail.body.encoded).to include(product_subscription.next_billing_date.strftime('%B %d, %Y'))
    end
  end

  describe '#payment_failed' do
    it 'sends payment failed email to customer' do
      mail = SubscriptionMailer.payment_failed(product_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Payment Failed')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(product.name)
      expect(mail.body.encoded).to include('could not be processed')
    end

    it 'includes customer portal link for payment update' do
      mail = SubscriptionMailer.payment_failed(product_subscription)

      expect(mail.body.encoded).to include('Manage your subscription')
      expect(mail.body.encoded).to include('update your payment method')
    end
  end

  describe '#subscription_cancelled' do
    before do
      product_subscription.update!(
        status: :cancelled,
        cancelled_at: Time.current,
        cancellation_reason: 'Customer request'
      )
    end

    it 'sends cancellation confirmation to customer' do
      mail = SubscriptionMailer.subscription_cancelled(product_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Subscription Cancelled')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(product.name)
      expect(mail.body.encoded).to include('has been cancelled')
    end

    it 'includes cancellation details in email' do
      mail = SubscriptionMailer.subscription_cancelled(product_subscription)

      expect(mail.body.encoded).to include(product_subscription.cancelled_at.strftime('%B %d, %Y'))
      expect(mail.body.encoded).to include('Customer request')
    end

    it 'includes reactivation information' do
      mail = SubscriptionMailer.subscription_cancelled(product_subscription)

      expect(mail.body.encoded).to include('reactivate')
      expect(mail.body.encoded).to include('contact us')
    end
  end

  describe '#permanent_failure' do
    before do
      product_subscription.update!(
        status: :failed,
        failure_reason: 'Maximum retry attempts exceeded'
      )
    end

    it 'sends permanent failure notification' do
      mail = SubscriptionMailer.permanent_failure(product_subscription)

      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.subject).to include('Subscription Cancelled')
      expect(mail.body.encoded).to include(CGI.escapeHTML(tenant_customer.full_name))
      expect(mail.body.encoded).to include(product.name)
      expect(mail.body.encoded).to include('multiple payment attempts')
    end

    it 'includes reactivation instructions' do
      mail = SubscriptionMailer.permanent_failure(product_subscription)

      expect(mail.body.encoded).to include('Updating your payment method')
      expect(mail.body.encoded).to include('contact us')
      expect(mail.body.encoded).to include('reactivate')
    end
  end
end 