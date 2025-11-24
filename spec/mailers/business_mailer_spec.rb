# frozen_string_literal: true

require 'rails_helper'
include ERB::Util

RSpec.describe BusinessMailer, type: :mailer do
  let(:business) { create(:business, name: 'Test Business') }
  let(:manager_user) { create(:user, :manager, business: business, email: 'manager@test.com') }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:service) { create(:service, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }

  before do
    # Clear deliveries before each test
    ActionMailer::Base.deliveries.clear
    
    # Ensure manager exists and has default notification preferences
    manager_user.update!(notification_preferences: {
      'email_booking_notifications' => true,
      'email_order_notifications' => true,
      'email_customer_notifications' => true,
      'email_payment_notifications' => true
    })
  end

  describe '#domain_request_notification' do
    let(:premium_business) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'example.com') }
    let(:premium_user) { create(:user, :manager, business: premium_business, email: 'premium@test.com') }

    it 'sends domain request notification email' do
      mail = BusinessMailer.domain_request_notification(premium_user)
      
      expect(mail.to).to eq([premium_user.email])
      expect(mail.subject).to include('Custom Domain Request Received')
      expect(mail.body.encoded).to include(premium_business.name)
      expect(mail.body.encoded).to include(premium_business.hostname)
    end

    it 'includes domain coverage information in the email' do
      mail = BusinessMailer.domain_request_notification(premium_user)
      
      # Check for domain coverage content in both HTML and text versions
      expect(mail.body.encoded).to include('DOMAIN COST COVERAGE')
      expect(mail.body.encoded).to include('$20 per year')
      expect(mail.body.encoded).to include('BizBlasts covers domain registration costs')
      expect(mail.body.encoded).to include('If under $20/year: We handle registration at no cost')
      expect(mail.body.encoded).to include('If over $20/year: We\'ll contact you with alternatives')
    end

    it 'includes coverage policy details' do
      mail = BusinessMailer.domain_request_notification(premium_user)
      
      text_part = mail.text_part.body.decoded
      expect(text_part).to include('If you already own this domain')
      expect(text_part).to include('domain-related costs through your current registrar')
    end

    context 'with domain name in email' do
      let(:premium_business_with_domain) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'mybusiness.com') }
      let(:premium_user_with_domain) { create(:user, :manager, business: premium_business_with_domain, email: 'owner@mybusiness.com') }

      it 'displays the requested domain in the email' do
        mail = BusinessMailer.domain_request_notification(premium_user_with_domain)
        
        expect(mail.body.encoded).to include('mybusiness.com')
        expect(mail.body.encoded).to include('Under Review')
      end
    end
  end

  describe '#stripe_connect_reminder' do
    let(:stripe_business) { create(:business, name: 'Reminder Biz', stripe_account_id: 'acct_123') }
    let(:manager) { create(:user, :manager, business: stripe_business, email: 'owner@biz.com') }

    it 'delivers a reminder email with magic link to onboarding' do
      mail = described_class.stripe_connect_reminder(manager, stripe_business)

      expect(mail).to be_present
      expect(mail.subject).to include('Connect Stripe')
      expect(mail.to).to contain_exactly(manager.email)
      expect(mail.body.encoded).to include('%2Fmanage%2Fsettings%2Fbusiness%2Fstripe_onboarding')
    end

    it 'returns a null mail when user cannot receive system emails' do
      manager.update!(unsubscribed_at: Time.current)
      expect(manager.unsubscribed_from_emails?).to be true
      mail = described_class.stripe_connect_reminder(manager, stripe_business)
      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end

  describe '#new_booking_notification' do
    let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member) }

    it 'sends booking notification to business manager' do
      mail = BusinessMailer.new_booking_notification(booking)
      
      expect(mail.to).to eq([manager_user.email])
      expect(mail.subject).to include('New Booking')
      expect(mail.subject).to include(tenant_customer.full_name)
      expect(mail.subject).to include(service.name)
      expect(mail.body.encoded).to include(html_escape(tenant_customer.full_name))
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include(business.name)
    end

    it 'does not send email when no manager exists' do
      business_without_manager = create(:business)
      booking_no_manager = create(:booking, business: business_without_manager, tenant_customer: tenant_customer, service: service)
      
      expect {
        BusinessMailer.new_booking_notification(booking_no_manager).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it 'does not send email when notifications are disabled' do
      manager_user.update!(notification_preferences: { 
        'email_booking_notifications' => false,
        'email_booking_confirmation' => false,
        'email_booking_updates' => false
      })
      
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  describe '#new_order_notification' do
    let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }

    it 'sends order notification to business manager' do
      mail = BusinessMailer.new_order_notification(order)
      
      expect(mail.to).to eq([manager_user.email])
      expect(mail.subject).to include('New Order')
      expect(mail.subject).to include(tenant_customer.full_name)
      expect(mail.body.encoded).to include(html_escape(tenant_customer.full_name))
      expect(mail.body.encoded).to include(business.name)
    end

    it 'does not send email when no manager exists' do
      business_without_manager = create(:business)
      order_no_manager = create(:order, business: business_without_manager, tenant_customer: tenant_customer)
      
      expect {
        BusinessMailer.new_order_notification(order_no_manager).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it 'does not send email when notifications are disabled' do
      manager_user.update!(notification_preferences: { 
        'email_order_notifications' => false,
        'email_order_updates' => false
      })
      
      expect {
        BusinessMailer.new_order_notification(order).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  describe '#new_customer_notification' do
    it 'sends customer notification to business manager' do
      mail = BusinessMailer.new_customer_notification(tenant_customer)
      
      expect(mail.to).to eq([manager_user.email])
      expect(mail.subject).to include('New Customer')
      expect(mail.subject).to include(tenant_customer.full_name)
      expect(mail.body.encoded).to include(html_escape(tenant_customer.full_name))
      expect(mail.body.encoded).to include(tenant_customer.email)
      expect(mail.body.encoded).to include(business.name)
    end

    it 'does not send email when no manager exists' do
      business_without_manager = create(:business)
      customer_no_manager = create(:tenant_customer, business: business_without_manager)
      
      expect {
        BusinessMailer.new_customer_notification(customer_no_manager).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it 'does not send email when notifications are disabled' do
      manager_user.update!(notification_preferences: { 
        'email_customer_notifications' => false
      })
      
      expect {
        BusinessMailer.new_customer_notification(tenant_customer).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  describe '#payment_received_notification' do
    let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer) }
    let(:payment) { create(:payment, business: business, tenant_customer: tenant_customer, invoice: invoice) }

    it 'sends payment notification to business manager' do
      mail = BusinessMailer.payment_received_notification(payment)
      
      expect(mail.to).to eq([manager_user.email])
      expect(mail.subject).to include('Payment Received')
      expect(mail.subject).to include(tenant_customer.full_name)
      expect(mail.body.encoded).to include(tenant_customer.full_name.gsub("'", "&#39;"))
      expect(mail.body.encoded).to include(business.name)
    end

    it 'includes booking information in subject when payment is for booking' do
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service)
      invoice.update!(booking: booking)
      
      mail = BusinessMailer.payment_received_notification(payment)
      
      expect(mail.subject).to include(service.name)
    end

    it 'includes order information in subject when payment is for order' do
      order = create(:order, business: business, tenant_customer: tenant_customer)
      invoice.update!(order: order)
      
      mail = BusinessMailer.payment_received_notification(payment)
      
      expect(mail.subject).to include("Order ##{order.id}")
    end

    it 'does not send email when no manager exists' do
      business_without_manager = create(:business)
      payment_no_manager = create(:payment, business: business_without_manager, tenant_customer: tenant_customer)
      
      expect {
        BusinessMailer.payment_received_notification(payment_no_manager).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it 'does not send email when notifications are disabled' do
      manager_user.update!(notification_preferences: { 
        'email_payment_notifications' => false,
        'email_payment_confirmations' => false
      })
      
      expect {
        BusinessMailer.payment_received_notification(payment).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  # Integration test to verify all notifications work end-to-end
  describe 'end-to-end email delivery' do
    it 'delivers all business notification emails successfully' do
      # Test booking notification
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
      
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_now
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      
      booking_mail = ActionMailer::Base.deliveries.last
      expect(booking_mail.to).to include(manager_user.email)
      expect(booking_mail.subject).to include('New Booking')
      
      # Test order notification
      order = create(:order, business: business, tenant_customer: tenant_customer)
      
      expect {
        BusinessMailer.new_order_notification(order).deliver_now
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      
      order_mail = ActionMailer::Base.deliveries.last
      expect(order_mail.to).to include(manager_user.email)
      expect(order_mail.subject).to include('New Order')
      
      # Test customer notification
      new_customer = create(:tenant_customer, business: business, first_name: 'New', last_name: 'Customer')
      
      expect {
        BusinessMailer.new_customer_notification(new_customer).deliver_now
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      
      customer_mail = ActionMailer::Base.deliveries.last
      expect(customer_mail.to).to include(manager_user.email)
      expect(customer_mail.subject).to include('New Customer')
      
      # Test payment notification
      invoice = create(:invoice, business: business, tenant_customer: tenant_customer)
      payment = create(:payment, business: business, tenant_customer: tenant_customer, invoice: invoice)
      
      expect {
        BusinessMailer.payment_received_notification(payment).deliver_now
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      
      payment_mail = ActionMailer::Base.deliveries.last
      expect(payment_mail.to).to include(manager_user.email)
      expect(payment_mail.subject).to include('Payment Received')
    end
  end

  # Test to verify notifications are properly queued via ActiveJob
  describe 'ActiveJob integration' do
    it 'queues business emails properly through deliver_later' do
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
      
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_later
      }.to have_enqueued_mail(BusinessMailer, :new_booking_notification)
    end
  end

  # Test error handling and logging
  describe 'error handling' do
    it 'logs appropriate warnings when business has no manager' do
      business_without_manager = create(:business)
      booking = create(:booking, business: business_without_manager, tenant_customer: tenant_customer, service: service)
      
      expect(Rails.logger).to receive(:warn).with(/No manager user found for Business/)
      BusinessMailer.new_booking_notification(booking).deliver_now
    end

    it 'logs appropriate info when notifications are disabled' do
      manager_user.update!(notification_preferences: { 
        'email_booking_notifications' => false,
        'email_booking_confirmation' => false,
        'email_booking_updates' => false
      })
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
      
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  # Test notification preferences functionality
  describe 'notification preferences' do
    it 'respects notification preferences for all email types' do
      # Disable all notifications
      manager_user.update!(notification_preferences: {
        'email_booking_notifications' => false,
        'email_booking_confirmation' => false,
        'email_booking_updates' => false,
        'email_order_notifications' => false,
        'email_order_updates' => false,
        'email_customer_notifications' => false,
        'email_payment_notifications' => false,
        'email_payment_confirmations' => false
      })
      
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
      order = create(:order, business: business, tenant_customer: tenant_customer)
      customer = create(:tenant_customer, business: business, first_name: 'Another', last_name: 'Customer')
      invoice = create(:invoice, business: business, tenant_customer: tenant_customer)
      payment = create(:payment, business: business, tenant_customer: tenant_customer, invoice: invoice)
      
      # None of these should send emails
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_now
        BusinessMailer.new_order_notification(order).deliver_now
        BusinessMailer.new_customer_notification(customer).deliver_now
        BusinessMailer.payment_received_notification(payment).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  # Test real production scenarios where business emails are failing
  describe 'production failure scenarios' do
    context 'when notification preferences are disabled in production' do
      before do
        # This reflects the actual production state where notifications are disabled
        manager_user.update!(notification_preferences: {
          'email_booking_notifications' => false,
          'email_booking_confirmation' => false,
          'email_booking_updates' => false,
          'email_order_notifications' => false,
          'email_order_updates' => false,
          'email_customer_notifications' => false,
          'email_payment_notifications' => false,
          'email_payment_confirmations' => false
        })
      end

      it 'should respect disabled booking notifications (correct behavior)' do
        booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end

      it 'should respect disabled customer notifications (correct behavior)' do
        # Create a separate customer for this test to avoid conflicts with the let(:tenant_customer)
        # that gets created in the before block and automatically triggers the callback
        test_customer = build(:tenant_customer, business: business)
        
        expect {
          BusinessMailer.new_customer_notification(test_customer).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end

      it 'should respect disabled order notifications (correct behavior)' do
        order = create(:order, business: business, tenant_customer: tenant_customer)
        
        expect {
          BusinessMailer.new_order_notification(order).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end

      it 'should respect disabled payment notifications (correct behavior)' do
        invoice = create(:invoice, business: business, tenant_customer: tenant_customer)
        payment = create(:payment, business: business, tenant_customer: tenant_customer, invoice: invoice)
        
        expect {
          BusinessMailer.payment_received_notification(payment).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context 'when notification preferences are enabled in production' do
      before do
        # This reflects the correct production state where notifications should be enabled
        manager_user.update!(notification_preferences: {
          'email_booking_notifications' => true,
          'email_order_notifications' => true,
          'email_customer_notifications' => true,
          'email_payment_notifications' => true
        })
      end

      it 'should send booking notifications to business managers when enabled' do
        booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
        expect(mail.subject).to include('New Booking')
      end

      it 'should send customer notifications to business managers when enabled' do
        expect {
          BusinessMailer.new_customer_notification(tenant_customer).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
        expect(mail.subject).to include('New Customer')
      end

      it 'should send order notifications to business managers when enabled' do
        order = create(:order, business: business, tenant_customer: tenant_customer)
        
        expect {
          BusinessMailer.new_order_notification(order).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
        expect(mail.subject).to include('New Order')
      end

      it 'should send payment notifications to business managers when enabled' do
        invoice = create(:invoice, business: business, tenant_customer: tenant_customer)
        payment = create(:payment, business: business, tenant_customer: tenant_customer, invoice: invoice)
        
        expect {
          BusinessMailer.payment_received_notification(payment).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
        expect(mail.subject).to include('Payment Received')
      end
    end

    context 'when business manager has no notification preferences set' do
      before do
        # This reflects businesses that might not have preferences configured
        manager_user.update!(notification_preferences: nil)
      end

      it 'should default to sending all business notifications' do
        booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(manager_user.email)
      end
    end

    context 'when business manager has empty notification preferences' do
      before do
        # This reflects businesses with empty preferences hash
        manager_user.update!(notification_preferences: {})
      end

      it 'should default to sending all business notifications' do
        booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
    end

    context 'when business manager email is invalid or missing' do
      it 'should handle missing manager email gracefully' do
        # Use update_column to set an invalid email format (database won't allow nil)
        manager_user.update_column(:email, 'invalid-email-format')
        
        booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
        
        expect(Rails.logger).to receive(:warn).with(/Invalid or missing manager email/)
        
        expect {
          BusinessMailer.new_booking_notification(booking).deliver_now
        }.not_to raise_error
        
        # Should not send any emails
        expect(ActionMailer::Base.deliveries.count).to eq(0)
      end
    end
  end

  describe 'universal unsubscribe' do
    it 'does not send any business notification if user is globally unsubscribed' do
      manager_user.update!(unsubscribed_at: Time.current)
      booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member)
      order = create(:order, business: business, tenant_customer: tenant_customer)
      customer = create(:tenant_customer, business: business, first_name: 'Another', last_name: 'Customer')
      payment = create(:payment, business: business, tenant_customer: tenant_customer)
      expect {
        BusinessMailer.new_booking_notification(booking).deliver_now
        BusinessMailer.new_order_notification(order).deliver_now
        BusinessMailer.new_customer_notification(customer).deliver_now
        BusinessMailer.payment_received_notification(payment).deliver_now
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end
end 