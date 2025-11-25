require 'rails_helper'

RSpec.describe EstimateToBookingService do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let(:service) do
    svc = create(:service, business: business, duration: 60, price: 100.0)
    ServicesStaffMember.create!(service: svc, staff_member: staff_member)
    svc.reload
  end
  let(:estimate) do
    est = create(:estimate,
      business: business,
      tenant_customer: tenant_customer,
      status: :approved,
      approved_at: Time.current,
      proposed_start_time: 1.week.from_now,
      proposed_end_time: 1.week.from_now + 2.hours,
      subtotal: 150.0,
      taxes: 15.0,
      total: 165.0,
      required_deposit: 50.0
    )
    est.estimate_items.first.update!(service: service, qty: 1, cost_rate: 150.0) if est.estimate_items.any?
    est
  end

  subject(:service_instance) { described_class.new(estimate) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "#call" do
    it "creates a booking" do
      expect { service_instance.call }.to change(Booking, :count).by(1)
    end

    it "sets correct booking attributes" do
      booking = service_instance.call

      expect(booking.business).to eq(business)
      expect(booking.tenant_customer).to eq(tenant_customer)
      expect(booking.start_time).to eq(estimate.proposed_start_time)
      expect(booking.end_time).to eq(estimate.proposed_end_time)
      expect(booking.service).to eq(service)
      expect(booking.status).to eq("pending")
    end

    it "associates booking with estimate" do
      booking = service_instance.call
      estimate.reload
      expect(estimate.booking).to eq(booking)
    end

    it "creates an invoice via Invoice.create_from_estimate" do
      expect(Invoice).to receive(:create_from_estimate).with(estimate).and_call_original
      service_instance.call
    end

    it "returns the booking if estimate already has one" do
      existing_booking = create(:booking, business: business, tenant_customer: tenant_customer, service: service)
      estimate.update!(booking: existing_booking)

      result = service_instance.call
      expect(result).to eq(existing_booking)
      expect(Booking.count).to eq(1) # No new booking created
    end

    it "uses primary service from first estimate item" do
      booking = service_instance.call
      expect(booking.service).to eq(estimate.estimate_items.first.service)
    end

    context "when proposed_end_time is nil" do
      before do
        estimate.update!(proposed_end_time: nil)
      end

      it "calculates end_time from service duration" do
        booking = service_instance.call
        expected_end = estimate.proposed_start_time + service.duration.minutes
        expect(booking.end_time).to eq(expected_end)
      end
    end

    it "wraps operations in a transaction" do
      allow(Booking).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Booking.new))

      expect { service_instance.call }.to raise_error(ActiveRecord::RecordInvalid)
      expect(estimate.reload.booking).to be_nil # Transaction rolled back
    end

    context "when estimate has inline customer fields but no tenant_customer" do
      let(:estimate_without_customer) do
        create(:estimate,
          business: business,
          tenant_customer: nil,
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com",
          phone: "+15551234567",
          address: "123 Main St",
          city: "Test City",
          state: "CA",
          zip: "12345",
          status: :approved,
          approved_at: Time.current,
          proposed_start_time: 1.week.from_now,
          subtotal: 150.0,
          taxes: 15.0,
          total: 165.0
        )
      end

      subject(:service_without_customer) { described_class.new(estimate_without_customer) }

      it "creates a tenant_customer from inline fields before creating booking" do
        expect { service_without_customer.call }.to change(TenantCustomer, :count).by(1)

        created_customer = TenantCustomer.last
        expect(created_customer.first_name).to eq("John")
        expect(created_customer.last_name).to eq("Doe")
        expect(created_customer.email).to eq("john@example.com")
        expect(created_customer.phone).to eq("+15551234567")
        expect(created_customer.address).to eq("123 Main St, Test City, CA, 12345")
        expect(created_customer.business).to eq(business)
      end

      it "successfully creates a booking with the new customer" do
        booking = service_without_customer.call
        expect(booking).to be_present
        expect(booking.tenant_customer).to be_present
        expect(booking.tenant_customer.email).to eq("john@example.com")
      end

      it "updates estimate with the created tenant_customer" do
        service_without_customer.call
        estimate_without_customer.reload
        expect(estimate_without_customer.tenant_customer).to be_present
        expect(estimate_without_customer.tenant_customer.email).to eq("john@example.com")
      end
    end
  end
end

