# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessSetupService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#setup_complete?' do
    context 'when business has no setup items completed' do
      it 'returns false' do
        expect(service.setup_complete?).to be false
      end
    end

    context 'when business has all setup items completed (service-based)' do
      before do
        # Set up a complete business with all required fields
        business.update!(
          stripe_account_id: 'acct_test123',
          description: 'A complete business description',
          phone: '555-1234',
          email: 'test@business.com',
          address: '123 Business St'
        )

        # Create a service
        business_service = create(:service, business: business, active: true)

        # Create a staff member with availability
        staff_member = create(:staff_member, business: business, active: true, availability: {
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        })

        # Associate the staff member with the service
        create(:services_staff_member, service: business_service, staff_member: staff_member)
      end

      it 'returns true' do
        expect(service.setup_complete?).to be true
      end
    end

    context 'when business has all setup items completed (product-based)' do
      before do
        # Set up a complete business with all required fields
        business.update!(
          stripe_account_id: 'acct_test123',
          description: 'A complete business description',
          phone: '555-1234',
          email: 'test@business.com',
          address: '123 Business St'
        )

        # Create a product
        create(:product, business: business, active: true)

        # Create shipping method for products
        create(:shipping_method, business: business, active: true)

        # Create tax rate for products
        create(:tax_rate, business: business)
      end

      it 'returns true' do
        expect(service.setup_complete?).to be true
      end
    end
  end

  describe '#todo_items' do
    it 'includes Stripe setup when not connected' do
      expect(service.todo_items).to include(
        hash_including(
          text: "Connect your Stripe account to accept payments",
          priority: :high
        )
      )
    end

    it 'excludes Stripe setup when connected' do
      business.update!(stripe_account_id: 'acct_test123')
      
      stripe_item = service.todo_items.find { |item| item[:text].include?("Stripe") }
      expect(stripe_item).to be_nil
    end

    it 'includes service/product setup when none exist' do
      expect(service.todo_items).to include(
        hash_including(
          text: "Add your first service or product to start taking orders",
          priority: :high
        )
      )
    end

    it 'excludes service/product setup when services exist' do
      create(:service, business: business, active: true)
      
      service_item = service.todo_items.find { |item| item[:text].include?("first service or product") }
      expect(service_item).to be_nil
    end

    it 'excludes service/product setup when products exist' do
      create(:product, business: business, active: true)
      
      service_item = service.todo_items.find { |item| item[:text].include?("first service or product") }
      expect(service_item).to be_nil
    end

    it 'includes availability setup when services exist but no availability' do
      create(:service, business: business, active: true)
      create(:staff_member, business: business, active: true, availability: {})
      
      expect(service.todo_items).to include(
        hash_including(
          text: "Set staff availability for your services",
          priority: :medium
        )
      )
    end

    it 'excludes availability setup when no services exist' do
      availability_item = service.todo_items.find { |item| item[:text].include?("availability") }
      expect(availability_item).to be_nil
    end

    it 'includes shipping setup when products exist but no shipping methods' do
      create(:product, business: business, active: true)
      
      expect(service.todo_items).to include(
        hash_including(
          text: "Set up shipping methods for your products",
          priority: :medium
        )
      )
    end

    it 'excludes shipping setup when no products exist' do
      shipping_item = service.todo_items.find { |item| item[:text].include?("shipping") }
      expect(shipping_item).to be_nil
    end

    it 'includes tax rate setup when products exist but no tax rates' do
      create(:product, business: business, active: true)

      expect(service.todo_items).to include(
        hash_including(
          text: "Configure tax rates for your products",
          priority: :low
        )
      )
    end

    it 'excludes tax rate setup when no products exist' do
      tax_item = service.todo_items.find { |item| item[:text].include?("tax rates") }
      expect(tax_item).to be_nil
    end

    it 'excludes tax rate setup when tax rates exist' do
      create(:product, business: business, active: true)
      create(:tax_rate, business: business)

      tax_item = service.todo_items.find { |item| item[:text].include?("tax rates") }
      expect(tax_item).to be_nil
    end

    context 'booking notifications todo' do
      let(:user) { create(:user, :manager, business: business) }
      let(:service_with_user) { described_class.new(business, user) }

      it 'includes booking notifications setup when services exist and notifications disabled' do
        create(:service, business: business, active: true)
        user.update!(notification_preferences: { 'email_booking_notifications' => false })

        expect(service_with_user.todo_items).to include(
          hash_including(
            key: :enable_booking_notifications,
            text: "Enable email notifications to be alerted when customers book services",
            priority: :medium
          )
        )
      end

      it 'excludes booking notifications setup when no services exist' do
        user.update!(notification_preferences: { 'email_booking_notifications' => false })

        booking_item = service_with_user.todo_items.find { |item| item[:key] == :enable_booking_notifications }
        expect(booking_item).to be_nil
      end

      it 'excludes booking notifications setup when notifications already enabled' do
        create(:service, business: business, active: true)
        user.update!(notification_preferences: { 'email_booking_notifications' => true })

        booking_item = service_with_user.todo_items.find { |item| item[:key] == :enable_booking_notifications }
        expect(booking_item).to be_nil
      end

      it 'excludes booking notifications setup when no user provided' do
        create(:service, business: business, active: true)

        # Service without user should not show the notification todo
        booking_item = service.todo_items.find { |item| item[:key] == :enable_booking_notifications }
        expect(booking_item).to be_nil
      end
    end

    context 'order notifications todo' do
      let(:user) { create(:user, :manager, business: business) }
      let(:service_with_user) { described_class.new(business, user) }

      it 'includes order notifications setup when products exist and notifications disabled' do
        create(:product, business: business, active: true)
        user.update!(notification_preferences: { 'email_order_notifications' => false })

        expect(service_with_user.todo_items).to include(
          hash_including(
            key: :enable_order_notifications,
            text: "Enable email notifications to be alerted when customers place orders",
            priority: :medium
          )
        )
      end

      it 'excludes order notifications setup when no products exist' do
        user.update!(notification_preferences: { 'email_order_notifications' => false })

        order_item = service_with_user.todo_items.find { |item| item[:key] == :enable_order_notifications }
        expect(order_item).to be_nil
      end

      it 'excludes order notifications setup when notifications already enabled' do
        create(:product, business: business, active: true)
        user.update!(notification_preferences: { 'email_order_notifications' => true })

        order_item = service_with_user.todo_items.find { |item| item[:key] == :enable_order_notifications }
        expect(order_item).to be_nil
      end

      it 'excludes order notifications setup when no user provided' do
        create(:product, business: business, active: true)

        # Service without user should not show the notification todo
        order_item = service.todo_items.find { |item| item[:key] == :enable_order_notifications }
        expect(order_item).to be_nil
      end
    end

    context 'rental notifications todo' do
      let(:user) { create(:user, :manager, business: business) }
      let(:service_with_user) { described_class.new(business, user) }

      it 'includes rental notifications setup when rentals exist and notifications disabled' do
        create(:product, :rental, business: business, active: true)
        user.update!(notification_preferences: { 'email_rental_notifications' => false })

        expect(service_with_user.todo_items).to include(
          hash_including(
            key: :enable_rental_notifications,
            text: "Enable email notifications to be alerted when customers book rentals",
            priority: :medium
          )
        )
      end

      it 'excludes rental notifications setup when no rentals exist' do
        user.update!(notification_preferences: { 'email_rental_notifications' => false })

        rental_item = service_with_user.todo_items.find { |item| item[:key] == :enable_rental_notifications }
        expect(rental_item).to be_nil
      end

      it 'excludes rental notifications setup when notifications already enabled' do
        create(:product, :rental, business: business, active: true)
        user.update!(notification_preferences: { 'email_rental_notifications' => true })

        rental_item = service_with_user.todo_items.find { |item| item[:key] == :enable_rental_notifications }
        expect(rental_item).to be_nil
      end

      it 'excludes rental notifications setup when no user provided' do
        create(:product, :rental, business: business, active: true)

        # Service without user should not show the notification todo
        rental_item = service.todo_items.find { |item| item[:key] == :enable_rental_notifications }
        expect(rental_item).to be_nil
      end
    end

    context 'estimate notifications todo' do
      let(:user) { create(:user, :manager, business: business) }
      let(:service_with_user) { described_class.new(business, user) }

      it 'includes estimate notifications setup when estimates exist and notifications disabled' do
        create(:estimate, business: business)
        user.update!(notification_preferences: { 'email_estimate_notifications' => false })

        expect(service_with_user.todo_items).to include(
          hash_including(
            key: :enable_estimate_notifications,
            text: "Enable email notifications to be alerted when customers request estimates",
            priority: :medium
          )
        )
      end

      it 'excludes estimate notifications setup when no estimates exist' do
        user.update!(notification_preferences: { 'email_estimate_notifications' => false })

        estimate_item = service_with_user.todo_items.find { |item| item[:key] == :enable_estimate_notifications }
        expect(estimate_item).to be_nil
      end

      it 'excludes estimate notifications setup when notifications already enabled' do
        create(:estimate, business: business)
        user.update!(notification_preferences: { 'email_estimate_notifications' => true })

        estimate_item = service_with_user.todo_items.find { |item| item[:key] == :enable_estimate_notifications }
        expect(estimate_item).to be_nil
      end

      it 'excludes estimate notifications setup when no user provided' do
        create(:estimate, business: business)

        # Service without user should not show the notification todo
        estimate_item = service.todo_items.find { |item| item[:key] == :enable_estimate_notifications }
        expect(estimate_item).to be_nil
      end
    end

    it 'includes loyalty program setup when not enabled' do
      expect(service.todo_items).to include(
        hash_including(
          text: "Set up a loyalty program to reward repeat customers",
          priority: :low
        )
      )
    end

    it 'excludes loyalty program setup when enabled' do
      business.update!(loyalty_program_enabled: true)
      
      loyalty_item = service.todo_items.find { |item| item[:text].include?("loyalty program") }
      expect(loyalty_item).to be_nil
    end

    it 'includes referral program setup when not enabled' do
      expect(service.todo_items).to include(
        hash_including(
          text: "Create a referral program to grow through word-of-mouth",
          priority: :low
        )
      )
    end

    it 'excludes referral program setup when enabled' do
      business.update!(referral_program_enabled: true)
      
      referral_item = service.todo_items.find { |item| item[:text].include?("referral program") }
      expect(referral_item).to be_nil
    end
  end

  describe '#high_priority_items' do
    it 'returns only high priority items' do
      high_priority_items = service.high_priority_items
      
      expect(high_priority_items).to all(include(priority: :high))
      expect(high_priority_items.count).to eq(2) # Stripe and Service/Product
    end
  end

  describe '#setup_summary' do
    context 'when setup is complete (service-based business)' do
      before do
        # Set up a complete business with all required fields
        business.update!(
          stripe_account_id: 'acct_test123',
          description: 'A complete business description',
          phone: '555-1234',
          email: 'test@business.com',
          address: '123 Business St'
        )

        # Create a service
        business_service = create(:service, business: business, active: true)

        # Create a staff member with availability
        staff_member = create(:staff_member, business: business, active: true, availability: {
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        })

        # Associate the staff member with the service
        create(:services_staff_member, service: business_service, staff_member: staff_member)
      end

      it 'returns completion message' do
        expect(service.setup_summary).to eq("Your business setup is complete! 🎉")
      end
    end

    context 'when setup is incomplete' do
      it 'returns task count summary' do
        expect(service.setup_summary).to match(/\d+ setup tasks? remaining \(\d+ high priority\)/)
      end
    end
  end

  describe 'URL generation' do
    it 'generates valid URLs for all todo items' do
      service.todo_items.each do |item|
        expect(item[:url]).to be_present
        expect(item[:url]).to start_with('/manage/')
      end
    end
  end

  describe 'todo_items filtering by user dismissals' do
    let(:user) { create(:user, :manager, business: business) }
    subject(:service_with_user) { described_class.new(business, user) }

    before do
      # Dismiss the stripe_connected task for this user
      user.setup_reminder_dismissals.create!(task_key: 'stripe_connected', dismissed_at: Time.current)
    end

    it 'excludes the dismissed task' do
      keys = service_with_user.todo_items.map { |item| item[:key].to_s }
      expect(keys).not_to include('stripe_connected')
      # Other tasks should still be present
      expect(keys).to include('add_service_or_product')
    end
  end
end 