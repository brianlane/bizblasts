# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /book without a bookable service', type: :request do
  let(:business) { create(:business) }

  before do
    host! host_for(business)
    ActsAsTenant.current_tenant = business
  end

  it 'redirects a missing service_id to the calendar' do
    create(:service, business: business, name: 'Hot Stone')

    get new_tenant_booking_path

    expect(response).to redirect_to(tenant_calendar_path)
    expect(flash[:alert]).to eq('Please choose a service to book.')
    expect(response).not_to have_http_status(:not_found)
  end

  it 'redirects an unknown service_id to the calendar' do
    create(:service, business: business)

    get new_tenant_booking_path, params: { service_id: 0 }

    expect(response).to redirect_to(tenant_calendar_path)
    expect(flash[:alert]).to eq('Please choose a service to book.')
  end

  it 'redirects a service_id that belongs to another tenant' do
    create(:service, business: business, name: 'Hot Stone')
    other = create(:business)
    other_service = ActsAsTenant.with_tenant(other) do
      create(:service, business: other, name: 'Other Tenant Secret Service')
    end

    get new_tenant_booking_path, params: { service_id: other_service.id }

    expect(response).to redirect_to(tenant_calendar_path)
    expect(flash[:alert]).to eq('Please choose a service to book.')
    expect(response.body).not_to include('Other Tenant Secret Service')
  end
end
