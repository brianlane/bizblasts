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

    context 'when business has all setup items completed' do
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
        
        # Create tax rate
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

    it 'includes tax rate setup when none exist' do
      expect(service.todo_items).to include(
        hash_including(
          text: "Configure tax rates for your location",
          priority: :low
        )
      )
    end

    it 'excludes tax rate setup when tax rates exist' do
      create(:tax_rate, business: business)
      
      tax_item = service.todo_items.find { |item| item[:text].include?("tax rates") }
      expect(tax_item).to be_nil
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
    context 'when setup is complete' do
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
        
        # Create tax rate
        create(:tax_rate, business: business)
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
end 