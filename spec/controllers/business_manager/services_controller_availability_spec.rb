# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessManager::ServicesController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business) }

  before do
    set_tenant_for_controller(controller: controller, business: business)
    sign_in(user)
  end

  describe 'GET #manage_availability' do
    context 'with valid service' do
      before do
        get :manage_availability, params: { id: service.id }
      end

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'assigns service availability manager' do
        expect(assigns(:availability_manager)).to be_a(ServiceAvailabilityManager)
      end

      it 'assigns date variables' do
        expect(assigns(:date)).to be_a(Date)
        expect(assigns(:start_date)).to be_a(Date)
        expect(assigns(:end_date)).to be_a(Date)
      end

      it 'assigns calendar data' do
        expect(assigns(:calendar_data)).to be_a(Hash)
      end

      it 'renders availability template' do
        expect(response).to render_template(:availability)
      end
    end

    context 'with specific date parameter' do
      let(:specific_date) { 2.weeks.from_now }

      before do
        get :manage_availability, params: { id: service.id, date: specific_date.to_s }
      end

      it 'uses the specified date' do
        expect(assigns(:date)).to eq(specific_date.to_date)
        expect(assigns(:start_date)).to eq(specific_date.beginning_of_week)
        expect(assigns(:end_date)).to eq(specific_date.end_of_week)
      end
    end

    context 'with invalid date parameter' do
      before do
        get :manage_availability, params: { id: service.id, date: 'invalid-date' }
      end

      it 'falls back to current date' do
        expect(assigns(:date)).to eq(Date.current)
      end
    end

    context 'with cache busting parameter' do
      before do
        allow(Rails.logger).to receive(:info)
        get :manage_availability, params: { id: service.id, bust_cache: 'true' }
      end

      it 'generates calendar data with cache busting' do
        expect(assigns(:calendar_data)).to be_a(Hash)
      end
    end
  end

  describe 'PATCH #manage_availability' do
    let(:availability_params) do
      {
        monday: {
          '0' => { start: '09:00', end: '17:00' },
          '1' => { start: '19:00', end: '21:00' }
        },
        tuesday: {
          '0' => { start: '10:00', end: '16:00' }
        },
        wednesday: {},
        thursday: {},
        friday: {},
        saturday: {},
        sunday: {}
      }
    end

    let(:full_day_params) do
      {
        monday: '0',
        tuesday: '0',
        wednesday: '1', # Full day
        thursday: '0',
        friday: '0',
        saturday: '0',
        sunday: '0'
      }
    end

    context 'with valid availability data' do
      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: availability_params },
          full_day: full_day_params,
          enforce_service_availability: '1'
        }
      end

      it 'redirects to services index' do
        expect(response).to redirect_to(business_manager_services_path)
      end

      it 'sets success message' do
        expect(flash[:notice]).to include('successfully updated')
        expect(flash[:notice]).to include(service.name)
      end

      it 'updates service availability' do
        service.reload
        expect(service.availability['monday']).to include({ 'start' => '09:00', 'end' => '17:00' })
        expect(service.availability['tuesday']).to include({ 'start' => '10:00', 'end' => '16:00' })
        expect(service.availability['wednesday']).to include({ 'start' => '00:00', 'end' => '23:59' })
      end

      it 'updates enforcement setting' do
        service.reload
        expect(service.enforce_service_availability?).to be true
      end
    end

    context 'with invalid availability data' do
      let(:invalid_params) do
        {
          monday: {
            '0' => { start: '17:00', end: '09:00' } # Invalid: end before start
          },
          tuesday: {},
          wednesday: {},
          thursday: {},
          friday: {},
          saturday: {},
          sunday: {}
        }
      end

      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: invalid_params }
        }
      end

      it 'renders availability template with errors' do
        expect(response).to render_template(:availability)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'sets error message' do
        expect(flash.now[:alert]).to be_present
      end

      it 'assigns calendar data for re-rendering' do
        expect(assigns(:calendar_data)).to be_a(Hash)
      end
    end

    context 'with overlapping slots' do
      let(:overlapping_params) do
        {
          monday: {
            '0' => { start: '09:00', end: '12:00' },
            '1' => { start: '11:00', end: '15:00' } # Overlaps with previous slot
          },
          tuesday: {},
          wednesday: {},
          thursday: {},
          friday: {},
          saturday: {},
          sunday: {}
        }
      end

      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: overlapping_params }
        }
      end

      it 'renders availability template with errors' do
        expect(response).to render_template(:availability)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'includes overlap error message' do
        expect(flash.now[:alert]).to include('Overlapping')
      end
    end

    context 'when service update fails' do
      before do
        allow_any_instance_of(Service).to receive(:update).and_return(false)
        allow_any_instance_of(Service).to receive(:errors).and_return(
          double(full_messages: ['Some validation error'])
        )

        patch :manage_availability, params: {
          id: service.id,
          service: { availability: availability_params }
        }
      end

      it 'renders availability template with errors' do
        expect(response).to render_template(:availability)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'sets error message' do
        expect(flash.now[:alert]).to be_present
      end
    end

    context 'when exception occurs' do
      before do
        allow_any_instance_of(ServiceAvailabilityManager).to receive(:update_availability).and_raise(StandardError.new('Test error'))

        patch :manage_availability, params: {
          id: service.id,
          service: { availability: availability_params }
        }
      end

      it 'redirects to services index with error' do
        expect(response).to redirect_to(business_manager_services_path)
        expect(flash[:alert]).to include('unexpected error')
      end
    end

    context 'with only enforcement setting update' do
      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: {} },
          enforce_service_availability: '0'
        }
      end

      it 'updates only the enforcement setting' do
        service.reload
        expect(service.enforce_service_availability?).to be false
      end
    end

    context 'with empty availability data' do
      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: {} },
          full_day: {
            monday: '0', tuesday: '0', wednesday: '0',
            thursday: '0', friday: '0', saturday: '0', sunday: '0'
          }
        }
      end

      it 'successfully updates with empty availability' do
        expect(response).to redirect_to(business_manager_services_path)
        expect(flash[:notice]).to include('successfully updated')
      end

      it 'clears all availability slots' do
        service.reload
        %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
          expect(service.availability[day]).to be_empty
        end
      end
    end
  end

  describe 'error handling' do
    context 'when service not found' do
      it 'raises ActiveRecord::RecordNotFound for GET' do
        expect {
          get :manage_availability, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises ActiveRecord::RecordNotFound for PATCH' do
        expect {
          patch :manage_availability, params: { id: 999999, service: { availability: {} } }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when user does not have access to service' do
      let(:other_business) { create(:business) }
      let(:other_service) { create(:service, business: other_business) }

      it 'raises ActiveRecord::RecordNotFound for GET' do
        expect {
          get :manage_availability, params: { id: other_service.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises ActiveRecord::RecordNotFound for PATCH' do
        expect {
          patch :manage_availability, params: { id: other_service.id, service: { availability: {} } }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'authorization' do
    context 'when user is not signed in' do
      before { sign_out(user) }

      it 'redirects to sign in page for GET' do
        get :manage_availability, params: { id: service.id }
        expect(response).to redirect_to(new_user_session_path)
      end

      it 'redirects to sign in page for PATCH' do
        patch :manage_availability, params: { id: service.id, service: { availability: {} } }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is a client (not manager)' do
      let(:client_user) { create(:user, :client) }

      before do
        sign_out(user)
        sign_in(client_user)
      end

      it 'denies access for GET' do
        expect {
          get :manage_availability, params: { id: service.id }
        }.to raise_error(Pundit::NotAuthorizedError)
      end

      it 'denies access for PATCH' do
        expect {
          patch :manage_availability, params: { id: service.id, service: { availability: {} } }
        }.to raise_error(Pundit::NotAuthorizedError)
      end
    end
  end

  describe 'parameter validation' do
    let(:malicious_params) do
      {
        monday: {
          '0' => { start: '<script>alert("xss")</script>', end: '17:00' }
        },
        tuesday: {},
        wednesday: {},
        thursday: {},
        friday: {},
        saturday: {},
        sunday: {}
      }
    end

    context 'with potentially malicious input' do
      before do
        patch :manage_availability, params: {
          id: service.id,
          service: { availability: malicious_params }
        }
      end

      it 'safely handles malicious input' do
        # The service object should filter out invalid time formats
        expect(response).to render_template(:availability)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'Use Default functionality' do
    let(:service_with_availability) do
      create(:service, business: business, 
             availability: { 'monday' => [{ 'start' => '09:00', 'end' => '17:00' }] },
             enforce_service_availability: true)
    end

    describe '#clearing_availability?' do
      it 'returns true when clearing availability with enforcement disabled' do
        controller.params = ActionController::Parameters.new({
          service: {
            availability: {},
            enforce_service_availability: false
          }
        })
        
        expect(controller.send(:clearing_availability?)).to be true
      end

      it 'returns true when clearing availability with string "false"' do
        controller.params = ActionController::Parameters.new({
          service: {
            availability: {},
            enforce_service_availability: 'false'
          }
        })
        
        expect(controller.send(:clearing_availability?)).to be true
      end

      it 'returns false when availability has data' do
        controller.params = ActionController::Parameters.new({
          service: {
            availability: { 'monday' => { '0' => { 'start' => '09:00', 'end' => '17:00' } } },
            enforce_service_availability: false
          }
        })
        
        expect(controller.send(:clearing_availability?)).to be false
      end

      it 'returns false when enforcement is enabled' do
        controller.params = ActionController::Parameters.new({
          service: {
            availability: {},
            enforce_service_availability: true
          }
        })
        
        expect(controller.send(:clearing_availability?)).to be false
      end

      it 'returns false when service params are missing' do
        controller.params = ActionController::Parameters.new({})
        expect(controller.send(:clearing_availability?)).to be false
      end

      it 'returns false when availability key is missing' do
        controller.params = ActionController::Parameters.new({
          service: { enforce_service_availability: false }
        })
        
        expect(controller.send(:clearing_availability?)).to be false
      end
    end

    describe 'PATCH #update with Use Default' do
      before do
        allow(controller).to receive(:set_service) { @service = service_with_availability }
      end

      context 'when clearing availability from edit page' do
        before do
          request.env['HTTP_REFERER'] = edit_business_manager_service_path(service_with_availability)
          
          patch :update, params: {
            id: service_with_availability.id,
            service: {
              availability: {},
              enforce_service_availability: false
            }
          }
        end

        it 'redirects back to edit page' do
          expect(response).to redirect_to(edit_business_manager_service_path(service_with_availability))
        end

        it 'shows specific success message' do
          expect(flash[:notice]).to eq('Service availability has been cleared. Using staff availability only.')
        end

        it 'clears availability data' do
          service_with_availability.reload
          expect(service_with_availability.availability.values.flatten.reject(&:blank?)).to be_empty
        end

        it 'disables enforcement' do
          service_with_availability.reload
          expect(service_with_availability.enforce_service_availability?).to be false
        end
      end

      context 'when clearing availability from other page' do
        before do
          request.env['HTTP_REFERER'] = business_manager_services_path
          
          patch :update, params: {
            id: service_with_availability.id,
            service: {
              availability: {},
              enforce_service_availability: false
            }
          }
        end

        it 'redirects to services index' do
          expect(response).to redirect_to(business_manager_services_path)
        end

        it 'shows generic success message' do
          expect(flash[:notice]).to eq('Service was successfully updated.')
        end
      end

      context 'with Turbo request' do
        before do
          request.headers['Accept'] = 'text/vnd.turbo-stream.html'
          
          patch :update, params: {
            id: service_with_availability.id,
            service: {
              availability: {},
              enforce_service_availability: false
            }
          }
        end

        it 'redirects to edit page for turbo streams' do
          expect(response).to redirect_to(edit_business_manager_service_path(service_with_availability))
        end
      end
    end

    describe 'regular update vs clearing availability' do
      before do
        allow(controller).to receive(:set_service) { @service = service_with_availability }
      end

      it 'handles regular updates normally' do
        patch :update, params: {
          id: service_with_availability.id,
          service: {
            name: 'Updated Name',
            availability: { 'monday' => { '0' => { 'start' => '10:00', 'end' => '18:00' } } },
            enforce_service_availability: true
          }
        }

        expect(response).to redirect_to(business_manager_services_path)
        expect(flash[:notice]).to eq('Service was successfully updated.')
      end
    end
  end

  # Helper method to properly set the tenant context for controller tests
  def set_tenant_for_controller(controller:, business:)
    allow(controller).to receive(:current_business).and_return(business)
    allow(controller).to receive(:set_tenant)
    ActsAsTenant.current_tenant = business
  end
end