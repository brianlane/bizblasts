require 'rails_helper'

RSpec.describe 'Rich Dropdown Functionality', type: :system, js: true do
  let(:business) { create(:business, host_type: 'subdomain') }
  let!(:services) { create_list(:service, 3, business: business) }
  let!(:staff_members) { create_list(:staff_member, 2, business: business) }
  
  before do
    ActsAsTenant.current_tenant = business
    Capybara.app_host = "http://#{host_for(business)}"
    # Associate staff with services for testing
    services.each { |service| create(:services_staff_member, service: service, staff_member: staff_members.first) }
  end

  context 'Calendar page service dropdown (reference implementation)' do
    before do
      visit tenant_calendar_path
    end

    it 'displays service dropdown correctly' do
      expect(page).to have_content('Select a service')
      expect(page).to have_css('.service-dropdown')
      expect(page).to have_css('[data-dropdown-target="button"]')
      expect(page).to have_css('[data-dropdown-target="menu"]', visible: false)
      
      # Check that the menu is hidden initially
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(menu[:class].include?('hidden')).to be_truthy
    end

    it 'opens dropdown when clicked' do
      find('[data-dropdown-target="button"]').click
      
      # Check that the menu is visible (not having .hidden class)
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(!menu[:class].include?('hidden')).to be_truthy
      expect(page).to have_css('.service-dropdown-button svg.rotate-180')
    end

    it 'displays all services with details' do
      find('[data-dropdown-target="button"]').click
      
      services.each do |service|
        within '[data-dropdown-target="menu"]' do
          expect(page).to have_content(service.name)
          expect(page).to have_content("$#{service.price}")
          expect(page).to have_content("#{service.duration} min")
        end
      end
    end

    it 'selects service and closes dropdown' do
      service = services.first
      
      find('[data-dropdown-target="button"]').click
      find('[data-dropdown-target="option"]', text: service.name).click
      
      # Check that the menu is hidden after selection
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(menu[:class].include?('hidden')).to be_truthy
      expect(page).to have_css('.service-dropdown-button svg:not(.rotate-180)')
      expect(find('.service-dropdown-text')).to have_content(service.name)
    end

    it 'enables view availability button after selection' do
      expect(find('#view-availability-btn')).to be_disabled
      
      find('[data-dropdown-target="button"]').click
      find('[data-dropdown-target="option"]', text: services.first.name).click
      
      expect(find('#view-availability-btn')).not_to be_disabled
    end

    it 'closes dropdown when clicking outside' do
      find('[data-dropdown-target="button"]').click
      # Check menu is open
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(!menu[:class].include?('hidden')).to be_truthy
      
      find('h1').click  # Click outside dropdown
      # Check menu is closed
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(menu[:class].include?('hidden')).to be_truthy
    end

    context 'mobile behavior', js: true do
      before do
        page.driver.resize_window(375, 667)  # iPhone size
      end

      it 'handles touch events correctly' do
        find('[data-dropdown-target="button"]').click
        # Check menu is open
        menu = find('[data-dropdown-target="menu"]', visible: false)
        expect(!menu[:class].include?('hidden')).to be_truthy
        
        find('[data-dropdown-target="option"]', text: services.first.name).click
        # Check menu is closed after selection
        menu = find('[data-dropdown-target="menu"]', visible: false)
        expect(menu[:class].include?('hidden')).to be_truthy
      end
    end
  end

  context 'Converted Forms (Rich Dropdown Implementation)' do    
    context 'Public Booking Form (Guest User)' do
      before do
        visit new_tenant_booking_path(service_id: services.first.id)
      end

      it 'displays guest booking form correctly' do
        expect(page).to have_content('Book Service')
        # Guest users shouldn't see staff selection
        expect(page).not_to have_content('Select Staff Member')
      end
    end

    context 'Public Booking Form (Business Manager)' do
      let(:manager_user) { create(:user, role: 'manager', business: business) }
      
      before do
        sign_in manager_user
        visit new_tenant_booking_path(service_id: services.first.id)
      end

      it 'displays rich staff dropdown for staff selection' do
        # Only managers/staff see staff selection dropdown
        expect(page).to have_content('Select Staff Member')
        expect(page).to have_css('.rich-dropdown')
        expect(page).to have_css('#public_booking_staff_dropdown')
        
        # Open staff dropdown  
        find('#public_booking_staff_dropdown [data-dropdown-target="button"]').click
        
        # Should show staff member
        within('#public_booking_staff_dropdown [data-dropdown-target="menu"]') do
          expect(page).to have_content(staff_members.first.name)
        end
      end

      it 'submits booking with correct staff member' do
        # Select staff member
        find('#public_booking_staff_dropdown [data-dropdown-target="button"]').click
        find('#public_booking_staff_dropdown [data-dropdown-target="option"]', text: staff_members.first.name).click
        
        # Check hidden field is updated
        hidden_field = find('#public_booking_staff_dropdown_hidden', visible: false)
        expect(hidden_field.value).to eq(staff_members.first.id.to_s)
      end
    end

    context 'Business Manager Service Form' do
      let(:manager_user) { create(:user, role: 'manager', business: business) }
      
      before do
        sign_in manager_user
        visit new_business_manager_service_path
      end

      it 'displays rich service type dropdown' do
        expect(page).to have_content('Service Type')
        expect(page).to have_css('.rich-dropdown')
        expect(page).to have_css('#service_type_dropdown')
        
        # Open service type dropdown
        find('#service_type_dropdown [data-dropdown-target="button"]').click
        
        # Should show service types
        within('#service_type_dropdown [data-dropdown-target="menu"]') do
          expect(page).to have_content('Standard')
          expect(page).to have_content('Experience')
          expect(page).to have_content('Event')
        end
      end
    end

    context 'Product Show Page' do
      let!(:product) { create(:product, business: business) }
      let!(:variants) { create_list(:product_variant, 2, product: product) }
      
      before do
        visit product_path(product)
      end

      it 'displays rich product variant dropdown' do
        expect(page).to have_content('Choose a variant:')
        expect(page).to have_css('.rich-dropdown')
        expect(page).to have_css('#product_variant_dropdown')
        
        # Open variant dropdown
        find('#product_variant_dropdown [data-dropdown-target="button"]').click
        
        # Should show variants with prices
        within('#product_variant_dropdown [data-dropdown-target="menu"]') do
          variants.each do |variant|
            expect(page).to have_content(variant.name)
          end
        end
      end
    end
  end

  context 'Accessibility' do
    before do
      visit tenant_calendar_path
    end

    it 'has proper ARIA attributes' do
      button = find('[data-dropdown-target="button"]')
      expect(button[:class]).to include('focus:outline-none')
      expect(button[:class]).to include('focus:ring-2')
    end
  end

  context 'Form Integration and Data Consistency' do
    let(:manager_user) { create(:user, role: 'manager', business: business) }
    
    before do
      sign_in manager_user
      visit new_tenant_booking_path(service_id: services.first.id)
    end

    it 'maintains same field names as collection_select' do
      # Check that form field names are preserved
      expect(page).to have_css('input[name="booking[service_id]"]', visible: false)
      expect(page).to have_css('input[name="booking[staff_member_id]"]', visible: false)
    end

    it 'triggers change events for form validation' do
      # Select staff member if dropdown exists
      if page.has_css?('#public_booking_staff_dropdown')
        find('#public_booking_staff_dropdown [data-dropdown-target="button"]').click
        find('#public_booking_staff_dropdown [data-dropdown-target="option"]', text: staff_members.first.name).click
      end
      
      # Verify no validation errors appear
      expect(page).to have_no_css('.error-message')
      expect(page).to have_no_css('.field_with_errors')
    end
  end
end 
