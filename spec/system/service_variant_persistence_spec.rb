# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Variant Persistence', type: :system do
  let!(:business) { create(:business, subdomain: 'testbiz') }
  let!(:service) { create(:service, business: business, name: 'Massage Service', price: 100.0, duration: 60) }
  let!(:staff_member) { create(:staff_member, business: business, name: 'John Doe') }
  
  # Create service variants
  let!(:variant_1) { create(:service_variant, service: service, name: '30 min', duration: 30, price: 75.0, position: 1) }
  let!(:variant_2) { create(:service_variant, service: service, name: '60 min', duration: 60, price: 100.0, position: 2) }
  let!(:variant_3) { create(:service_variant, service: service, name: '90 min', duration: 90, price: 125.0, position: 3) }

  before do
    # Associate staff with service
    create(:services_staff_member, service: service, staff_member: staff_member)
    # Set up subdomain
    host! "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
    driven_by(:rack_test)
  end

  describe 'Service variant persistence through public views' do
    context 'Happy path: Home -> Services -> Service Detail -> Calendar -> Booking' do
      it 'persists service variant selection through all views' do
        # Step 1: Start from home page
        visit '/'
        expect(page).to have_content(business.name)
        expect(page).to have_content('Massage Service')
        
        # Verify service variants are shown in home page with pricing
        within('.service-list-section') do
          expect(page).to have_content('Duration: 30-90 minutes')
          expect(page).to have_content('Price: $75.00 - $125.00')
        end

        # Step 2: Navigate to services page from home
        click_link 'Services'
        expect(current_path).to eq('/services')
        expect(page).to have_content('Our Services at')
        
        # Verify service variants are shown with price ranges
        expect(page).to have_content('Massage Service')
        expect(page).to have_content('Duration: 30-90 mins')
        expect(page).to have_content('Price: $75.00 - $125.00')

        # Step 3: Click "View Service" which should include default variant (first variant)
        click_link 'View Service'
        expect(current_path).to eq("/services/#{service.id}")
        expect(current_url).to include("service_variant_id=#{variant_1.id}")
        
        # Verify we're on service detail page with variant dropdown
        expect(page).to have_content('Massage Service')
        expect(page).to have_content('Choose Option')
        expect(page).to have_content('30 min (30 min)')  # Default selected variant
        
        # Step 4: Select a different variant (90 min)
        # Note: Since we're using rack_test driver, we'll simulate the selection
        # by directly visiting the URL with the selected variant
        visit "/services/#{service.id}?service_variant_id=#{variant_3.id}"
        
        # Verify the 90 min variant is now selected/displayed
        expect(current_url).to include("service_variant_id=#{variant_3.id}")
        expect(page).to have_content('90 min')
        expect(page).to have_content('$125.00')
        
        # Step 5: Click "Book Now" and verify variant persists to calendar
        click_link 'Book Now'
        expect(current_path).to eq('/calendar')
        expect(current_url).to include("service_id=#{service.id}")
        expect(current_url).to include("service_variant_id=#{variant_3.id}")
        expect(current_url).to include("staff_member_id=#{staff_member.id}")
        
        # Verify calendar shows correct service and variant info
        expect(page).to have_content('Book at')
        expect(page).to have_content('Massage Service')
        
        # Step 6: Navigate to booking page and verify variant persists
        # Simulate selecting a time slot (would normally be done via JavaScript)
        visit "/book?service_id=#{service.id}&service_variant_id=#{variant_3.id}&staff_member_id=#{staff_member.id}"
        
        expect(current_path).to eq('/book')
        expect(current_url).to include("service_id=#{service.id}")
        expect(current_url).to include("service_variant_id=#{variant_3.id}")
        
        # Verify booking form shows correct service and variant
        expect(page).to have_content('Book Service: Massage Service')
        # The variant should be pre-selected since we passed it in the URL
        expect(page).to have_field('booking_service_variant_id', with: variant_3.id.to_s, type: :hidden)
      end
    end

    context 'Navigation from generic pages/show view' do
      it 'includes service variant in links from generic pages' do
        # Visit the generic pages show view
        visit '/show'  # This would be the fallback generic view
        
        expect(page).to have_content(business.name)
        expect(page).to have_content('Our Services')
        expect(page).to have_content('Massage Service')
        
        # Verify service variants are used for pricing display
        expect(page).to have_content('Duration: 30-90 minutes')
        expect(page).to have_content('Price: $75.00 - $125.00')
        
        # Click "View Service" and verify it includes variant ID
        click_link 'View Service'
        expect(current_url).to include("service_variant_id=#{variant_1.id}")
        
        # Go back and click "Book Now"
        visit '/show'
        click_link 'Book Now'
        expect(current_url).to include("service_variant_id=#{variant_1.id}")
      end
    end

    context 'Services without variants' do
      let!(:simple_service) { create(:service, business: business, name: 'Simple Service', price: 50.0, duration: 30) }
      
      before do
        create(:services_staff_member, service: simple_service, staff_member: staff_member)
      end

      it 'handles services without variants correctly' do
        visit '/services'
        
        # Should show simple pricing for service without variants
        within(:xpath, "//h2[contains(text(), 'Simple Service')]/ancestor::div[contains(@class, 'border')]") do
          expect(page).to have_content('Duration: 30 mins')
          expect(page).to have_content('Price: $50.00')
          
          # Click "View Service" - should not include service_variant_id
          click_link 'View Service'
        end
        
        expect(current_path).to eq("/services/#{simple_service.id}")
        expect(current_url).not_to include('service_variant_id')
        
        # Verify no variant dropdown is shown
        expect(page).not_to have_content('Choose Option')
        expect(page).to have_content('Duration: 30 minutes')
        expect(page).to have_content('$50.00')
      end
    end
  end

  describe 'Auto-selection behavior' do
    context 'Service with single variant' do
      let!(:single_variant_service) { create(:service, business: business, name: 'Single Variant Service', price: 80.0) }
      let!(:single_variant) { create(:service_variant, service: single_variant_service, name: 'Standard', duration: 45, price: 80.0) }
      
      before do
        create(:services_staff_member, service: single_variant_service, staff_member: staff_member)
      end

      it 'auto-selects the single variant' do
        visit "/services/#{single_variant_service.id}"
        
        # Should auto-select the single variant
        expect(current_url).to include("service_variant_id=#{single_variant.id}")
        expect(page).to have_content('Standard (45 min)')
        
        # Book Now should include the variant ID
        click_link 'Book Now'
        expect(current_url).to include("service_variant_id=#{single_variant.id}")
      end
    end
  end
end 