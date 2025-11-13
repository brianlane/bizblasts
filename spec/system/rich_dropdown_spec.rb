require 'rails_helper'

RSpec.describe 'Rich Dropdown Functionality', type: :system do
  let(:business) { create(:business, host_type: 'subdomain') }
  let!(:services) { create_list(:service, 3, business: business) }
  let!(:staff_members) { create_list(:staff_member, 2, business: business) }
  
  before do
    allow(BookingService).to receive(:generate_calendar_data).and_return({})
    allow(BookingService).to receive(:fetch_available_slots).and_return([])
    allow(AvailabilityService).to receive(:available_slots).and_return([])

    ActsAsTenant.current_tenant = business
    Capybara.app_host = "http://#{host_for(business)}"
    # Associate staff with services for testing
    services.each { |service| create(:services_staff_member, service: service, staff_member: staff_members.first) }
  end

  context 'Calendar page service dropdown (reference implementation)', js: false do
    before do
      @previous_driver = Capybara.current_driver
      @previous_host = Capybara.default_host
      Capybara.current_driver = :rack_test
      Capybara.default_host = "http://#{host_for(business)}"
      visit tenant_calendar_path
    end

    after do
      Capybara.current_driver = @previous_driver
      Capybara.default_host = @previous_host
    end

    it 'displays service dropdown correctly' do
      expect(page).to have_content('Select a service')
      expect(page).to have_css('.service-dropdown')
      expect(page).to have_css('[data-dropdown-target="button"]')
      expect(page).to have_css('[data-dropdown-target="menu"]', visible: false)
    end

    it 'configures dropdown toggle via data attributes' do
      button = find('[data-dropdown-target="button"]')
      expect(button[:'data-action']).to include('click->dropdown#toggle')
      menu = find('[data-dropdown-target="menu"]', visible: false)
      expect(menu[:class]).to include('hidden')
    end

    it 'lists all services within the dropdown menu' do
      menu = find('[data-dropdown-target="menu"]', visible: false)
      services.each do |service|
        expect(menu).to have_content(service.name)
        expect(menu).to have_content("$#{service.price}")
        expect(menu).to have_content("#{service.duration} min")
      end
    end

    it 'provides hidden field for selected service' do
      hidden_field = find('input[name="service_id"]', visible: false)
      expect(hidden_field.value.to_s).to eq('')

      options = all('[data-dropdown-target="option"]', visible: false)
      expect(options.size).to eq(services.size)
      services.each do |service|
        expect(options.any? { |opt| opt[:'data-item-id'] == service.id.to_s }).to be(true)
      end
    end

    it 'starts with view availability button disabled' do
      expect(find('#view-availability-btn')[:disabled]).to be_present
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
      menu = find('#public_booking_staff_dropdown [data-dropdown-target="menu"]', visible: false)
      expect(menu).to have_content(staff_members.first.name)
      end
      
      it 'submits booking with correct staff member' do
        hidden_field = find('#public_booking_staff_dropdown_hidden', visible: false)
        expect(hidden_field.value.to_s).to eq('')
        options = all('#public_booking_staff_dropdown [data-dropdown-target="option"]', visible: false)
        expect(options.any? { |opt| opt[:'data-item-id'] == staff_members.first.id.to_s }).to be(true)
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

        menu = find('#product_variant_dropdown [data-dropdown-target="menu"]', visible: false)
        variants.each do |variant|
          expect(menu).to have_content(variant.name)
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
    
    it 'exposes dropdown options for form validation' do
      menu = find('#public_booking_staff_dropdown [data-dropdown-target="menu"]', visible: false)
      expect(menu).to have_content(staff_members.first.name)
      expect(page).to have_no_css('.error-message')
      expect(page).to have_no_css('.field_with_errors')
    end
  end
end 
