require 'rails_helper'

RSpec.describe 'Cache-Control headers on public endpoints', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant', stripe_account_id: 'acct_test', subscription_discount_enabled: true, loyalty_program_enabled: true, referral_program_enabled: true) }
  let!(:tenant_customer) { create(:tenant_customer, business: business) }
  let!(:service) { create(:service, business: business, price: 50.00, duration: 30, subscription_enabled: true, tips_enabled: true, service_type: :experience, min_bookings: 1, max_bookings: 1, spots: 1) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member, start_time: 1.day.from_now, end_time: 1.day.from_now + 30.minutes, status: :confirmed) }
  let!(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
  let!(:invoice) { create(:invoice, business: business, order: order, tenant_customer: tenant_customer, status: :pending) }

  before do
    ActsAsTenant.current_tenant = business
    host! "#{business.subdomain}.lvh.me"
  end

  it 'orders#show sets no-store header' do
    get order_path(order)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'booking#confirmation sets no-store header' do
    get tenant_booking_confirmation_path(booking)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'client_bookings#index sets no-store header' do
    user = create(:user, role: :client)
    sign_in user
    get tenant_my_bookings_path
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'tenant_calendar#index sets no-store header' do
    get tenant_calendar_path
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'tips#new sets no-store header' do
    get new_tip_path(booking_id: booking.id, token: booking.generate_tip_token)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'subscriptions#new sets no-store header' do
    get new_subscription_path(service_id: service.id)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'loyalty#show sets no-store header' do
    user = create(:user, role: :client)
    sign_in user
    get tenant_loyalty_path
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'referral#show sets no-store header' do
    user = create(:user, role: :client)
    sign_in user
    get tenant_referral_program_path
    expect(response.headers['Cache-Control']).to include('no-store')
  end
end 