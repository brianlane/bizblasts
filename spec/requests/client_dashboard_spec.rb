# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "ClientDashboard", type: :request do
  let!(:business) { create(:business) }
  let!(:client) { create(:user, :client) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: client.email) }

  before do
    sign_in client
  end

  describe "GET /dashboard" do
    it "renders the dashboard for a signed-in client" do
      get dashboard_path
      expect(response).to be_successful
      expect(response.body).to include("Dashboard")
    end

    context "with upcoming rental bookings" do
      let!(:rental_product) { create(:product, :rental, business: business, rental_quantity_available: 3, price: 50) }
      let!(:rental_booking) do
        create(:rental_booking,
               business: business,
               product: rental_product,
               tenant_customer: tenant_customer,
               start_time: 2.days.from_now,
               end_time: 3.days.from_now,
               status: 'pending_deposit')
      end

      it "displays upcoming rental bookings widget" do
        get dashboard_path
        expect(response).to be_successful
        expect(response.body).to include("Upcoming Rentals")
        expect(response.body).to include(rental_booking.rental_name)
      end
    end

    context "with recent estimates" do
      let!(:estimate) do
        ActsAsTenant.without_tenant do
          create(:estimate, business: business, tenant_customer: tenant_customer)
        end
      end

      it "displays recent estimates widget" do
        get dashboard_path
        expect(response).to be_successful
        expect(response.body).to include("Recent Estimates")
      end
    end

    context "with recent client documents" do
      let!(:document) do
        ActsAsTenant.without_tenant do
          create(:client_document, business: business, tenant_customer: tenant_customer, document_type: 'waiver', status: 'completed')
        end
      end

      it "displays waivers and documents widget" do
        get dashboard_path
        expect(response).to be_successful
        expect(response.body).to include("Waivers")
        expect(response.body).to include("Documents")
      end
    end

    context "with no tenant customer records" do
      let!(:other_client) { create(:user, :client) }

      before do
        sign_out client
        sign_in other_client
      end

      it "still renders the dashboard without errors" do
        get dashboard_path
        expect(response).to be_successful
      end
    end
  end
end
