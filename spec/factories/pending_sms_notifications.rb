FactoryBot.define do
  factory :pending_sms_notification do
    association :business
    association :tenant_customer

    notification_type { 'booking_confirmation' }
    sms_type { 'booking' }
    phone_number { tenant_customer&.phone || '+15551234567' }

    template_data do
      {
        service_name: 'Test Service',
        date: Date.current.strftime('%m/%d/%Y'),
        time: '10:00 AM',
        business_name: business&.name || 'Test Business',
        address: '123 Test St'
      }
    end

    queued_at { Time.current }
    expires_at { 7.days.from_now }
    status { 'pending' }

    # Generate unique deduplication key
    sequence(:deduplication_key) do |n|
      time_bucket = (Time.current.to_i / 24.hours).to_i
      "#{notification_type}:#{business&.id}:#{tenant_customer&.id}:#{time_bucket}:#{n}"
    end

    # Traits for different states
    trait :sent do
      status { 'sent' }
      processed_at { Time.current }
    end

    trait :failed do
      status { 'failed' }
      failed_at { Time.current }
      failure_reason { 'Customer not opted in for SMS notifications' }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 1.day.ago }
    end

    # Traits for different notification types
    trait :booking_confirmation do
      association :booking
      notification_type { 'booking_confirmation' }
      sms_type { 'booking' }
      template_data do
        {
          service_name: booking&.service&.name || 'Test Service',
          date: booking&.local_start_time&.strftime('%m/%d/%Y') || Date.current.strftime('%m/%d/%Y'),
          time: booking&.local_start_time&.strftime('%I:%M %p') || '10:00 AM',
          business_name: business&.name || 'Test Business',
          address: business&.address || '123 Test St'
        }
      end
    end

    trait :booking_reminder do
      association :booking
      notification_type { 'booking_reminder' }
      sms_type { 'reminder' }
      template_data do
        {
          service_name: booking&.service&.name || 'Test Service',
          date: booking&.local_start_time&.strftime('%m/%d/%Y') || Date.current.strftime('%m/%d/%Y'),
          time: booking&.local_start_time&.strftime('%I:%M %p') || '10:00 AM',
          business_name: business&.name || 'Test Business',
          timeframe_text: 'tomorrow'
        }
      end
    end

    trait :invoice_created do
      association :invoice
      notification_type { 'invoice_created' }
      sms_type { 'payment' }
      template_data do
        {
          invoice_number: invoice&.invoice_number || 'INV-001',
          amount: '$100.00',
          date: invoice&.due_date&.strftime('%m/%d/%Y') || Date.current.strftime('%m/%d/%Y'),
          business_name: business&.name || 'Test Business'
        }
      end
    end

    trait :invoice_payment_confirmation do
      association :invoice
      notification_type { 'invoice_payment_confirmation' }
      sms_type { 'payment' }
      template_data do
        {
          invoice_number: invoice&.invoice_number || 'INV-001',
          amount: '$100.00',
          business_name: business&.name || 'Test Business'
        }
      end
    end

    trait :order_confirmation do
      association :order
      notification_type { 'order_confirmation' }
      sms_type { 'order' }
      template_data do
        {
          order_number: order&.order_number || 'ORD-001',
          amount: '$50.00',
          business_name: business&.name || 'Test Business'
        }
      end
    end

    # Callback to ensure business consistency
    after(:build) do |notification|
      notification.business ||= notification.tenant_customer&.business ||
                                notification.booking&.business ||
                                notification.invoice&.business ||
                                notification.order&.business
    end
  end
end
