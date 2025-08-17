# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Order, type: :model do
  describe '#booking_time_passed?' do
    let(:business) { create(:business) }
    let(:tenant_customer) { create(:tenant_customer, business: business) }
    let(:service_duration) { 60 } # minutes
    let(:service) { create(:service, business: business, duration: service_duration) }

    context 'when booking duration has elapsed' do
      let(:start_time) { 2.hours.ago }
      let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, start_time: start_time) }
      let(:order) { create(:order, tenant_customer: tenant_customer, business: business, booking: booking, order_type: :service, status: :processing) }

      it 'returns true' do
        expect(order.booking_time_passed?).to be true
      end
    end

    context 'when booking duration has not yet elapsed' do
      let(:start_time) { 10.minutes.ago }
      let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, start_time: start_time) }
      let(:order) { create(:order, tenant_customer: tenant_customer, business: business, booking: booking, order_type: :service, status: :processing) }

      it 'returns false' do
        expect(order.booking_time_passed?).to be false
      end
    end
  end
end
