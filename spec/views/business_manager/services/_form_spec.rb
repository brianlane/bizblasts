# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'business_manager/services/_form', type: :view do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  
  before do
    set_tenant(business)
    allow(view).to receive(:current_user).and_return(user)
    allow(view).to receive(:current_business).and_return(business)
  end

  describe 'dynamic button visibility for service availability' do
    context 'for new services' do
      let(:service) { build(:service, business: business) }

      before do
        assign(:current_business, business)
        render partial: 'business_manager/services/form', locals: { service: service }
      end

      it 'shows Configure Availability button initially' do
        expect(rendered).to have_css('#configure-availability-btn', text: 'Configure Availability')
      end

      it 'hides Use Default button initially (button is present but not visible)' do
        expect(rendered).to have_css('#disable-availability-btn', visible: :hidden)
      end

      it 'includes service availability controller data attributes' do
        expect(rendered).to have_css('[data-controller*="service-availability"]')
        expect(rendered).to have_css('[data-action*="click->service-availability#showAvailabilityForm"]')
        # `hideAvailabilityForm` action is on the hidden button, so search among hidden elements
        expect(rendered).to have_css('[data-action*="click->service-availability#hideAvailabilityForm"]', visible: :hidden)
      end

      it 'includes embedded availability form container (initially hidden)' do
        expect(rendered).to have_css('#availability-form-container.hidden')
      end

      it 'includes enforcement hidden field with value 1' do
        expect(rendered).to have_css('input[name="service[enforce_service_availability]"][value="1"]', visible: false)
      end
    end

    context 'for existing services with availability' do
      let(:service) do
        create(:service, business: business,
               availability: { 'monday' => [{ 'start' => '09:00', 'end' => '17:00' }] },
               enforce_service_availability: true)
      end

      before do
        assign(:current_business, business)
        render partial: 'business_manager/services/form', locals: { service: service }
      end

      it 'shows Current Availability section' do
        expect(rendered).to have_text('Current Availability')
        expect(rendered).to have_text('Enforcement enabled')
        expect(rendered).to have_text('time slots configured')
      end

      it 'shows Manage Availability button' do
        expect(rendered).to have_link('Manage Availability', 
                                      href: manage_availability_business_manager_service_path(service))
      end

      it 'shows Use Default button for existing services' do
        expect(rendered).to have_button('Use Default (Staff Availability Only)')
      end

      it 'Use Default button form has correct action and method' do
        expect(rendered).to have_button('Use Default (Staff Availability Only)')
      end

      it 'includes confirmation dialog for Use Default button' do
        expect(rendered).to match(/This will remove all service availability restrictions/)
      end
    end

    context 'for existing services without availability' do
      let(:service) do
        create(:service, business: business,
               availability: {},
               enforce_service_availability: false)
      end

      before do
        assign(:current_business, business)
        render partial: 'business_manager/services/form', locals: { service: service }
      end

      it 'shows enforcement disabled status' do
        expect(rendered).to have_text('Enforcement disabled')
        expect(rendered).to have_text('service available when staff are available')
      end

      it 'does not show slot count when enforcement is disabled' do
        expect(rendered).not_to have_text('time slots configured')
      end
    end
  end

  describe 'slot counting logic' do
    context 'with various availability data' do
      it 'counts valid slots correctly' do
        service = create(:service, business: business,
                         availability: {
                           'monday' => [
                             { 'start' => '09:00', 'end' => '12:00' },
                             { 'start' => '13:00', 'end' => '17:00' }
                           ],
                           'tuesday' => [{ 'start' => '10:00', 'end' => '16:00' }],
                           'wednesday' => []
                         },
                         enforce_service_availability: true)
        
        assign(:current_business, business)
        render partial: 'business_manager/services/form', locals: { service: service }
        
        expect(rendered).to have_text('3 time slots configured')
      end

      it 'handles empty slots correctly' do
        service = create(:service, business: business,
                         availability: {
                           'monday' => [],
                           'tuesday' => [nil, '', {}].compact,
                           'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }]
                         },
                         enforce_service_availability: true)
        
        assign(:current_business, business)  
        render partial: 'business_manager/services/form', locals: { service: service }
        
        expect(rendered).to have_text('1 time slots configured')
      end
    end
  end

  describe 'form structure and data attributes' do
    let(:service) { build(:service, business: business) }

    before do
      assign(:current_business, business)
      render partial: 'business_manager/services/form', locals: { service: service }
    end

    it 'includes service-availability controller' do
      expect(rendered).to have_css('[data-controller*="service-availability"]')
    end

    it 'includes service name value for the controller' do
      expect(rendered).to have_css('[data-service-availability-service-name-value]')
    end

    it 'has availability form container with proper targets' do
      expect(rendered).to have_css('#availability-form-container[data-service-availability-target="availabilityContainer"]')
    end

    it 'includes proper button actions' do
      expect(rendered).to have_css('[data-action="click->service-availability#showAvailabilityForm"]')
      expect(rendered).to have_css('[data-action="click->service-availability#hideAvailabilityForm"]', visible: :hidden)
    end
  end

  private

  def set_tenant(business)
    ActsAsTenant.current_tenant = business
  end
end