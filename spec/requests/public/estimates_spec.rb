require 'rails_helper'

RSpec.describe "/e/:token", type: :request do
  let(:business) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:estimate) { create(:estimate, business: business, tenant_customer: customer, status: :sent, required_deposit: 50.0) }

  before do
    host! "#{business.subdomain}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /show" do
    it "renders a successful response" do
      get tenant_estimate_path(estimate.token)
      expect(response).to be_successful
    end
  end

  describe "POST /approve" do
    it "approves the estimate and redirects to payment" do
      patch approve_tenant_estimate_path(estimate.token)
      estimate.reload
      expect(estimate.status).to eq("approved")
      expect(response).to redirect_to(new_tenant_payment_path(invoice_id: estimate.booking.invoice.id))
    end

    it "creates a booking and an invoice" do
      expect {
        patch approve_tenant_estimate_path(estimate.token)
      }.to change(Booking, :count).by(1).and change(Invoice, :count).by(1)
    end

    context "when no deposit is required" do
      let!(:estimate_no_deposit) { create(:estimate, business: business, tenant_customer: customer, status: :sent, required_deposit: 0) }
      it "redirects to the estimate page with a notice" do
        patch approve_tenant_estimate_path(estimate_no_deposit.token)
        expect(flash[:notice]).to eq('Estimate approved. No deposit was required.')
        expect(response).to redirect_to(tenant_estimate_path(estimate_no_deposit.token))
      end
    end
  end

  describe "POST /decline" do
    it "declines the estimate and redirects" do
      patch decline_tenant_estimate_path(estimate.token)
      estimate.reload
      expect(estimate.status).to eq("declined")
      expect(response).to redirect_to(tenant_estimate_path(estimate.token))
      expect(flash[:notice]).to eq('You have declined this estimate.')
    end
  end

  describe "POST /request_changes" do
    it "sends a notification and redirects" do
      expect {
        patch request_changes_tenant_estimate_path(estimate.token), params: { changes_request: "More cowbell" }
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'request_changes_notification', 'deliver_now', args: [estimate, "More cowbell"])

      expect(response).to redirect_to(tenant_estimate_path(estimate.token))
      expect(flash[:notice]).to eq('Your change request has been sent.')
    end
  end
end 