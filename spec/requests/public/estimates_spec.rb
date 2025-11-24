require 'rails_helper'

RSpec.describe "Public::Estimates", type: :request do
  let(:business) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:service) do 
    svc = create(:service, business: business, duration: 60)
    # Associate service with staff member
    ServicesStaffMember.create!(service: svc, staff_member: staff_member)
    svc.reload
    svc
  end
  let!(:estimate) do
    est = create(:estimate, business: business, tenant_customer: customer, status: :sent, required_deposit: 50.0, proposed_start_time: 1.week.from_now, proposed_end_time: 1.week.from_now + 2.hours)
    est.estimate_items.first.update!(service: service) if est.estimate_items.any?
    est
  end

  before do
    host! "#{business.subdomain}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /estimates/:token (show)" do
    it "renders a successful response" do
      get public_estimate_path(token: estimate.token)
      expect(response).to be_successful
    end

    it "marks the estimate as viewed if it was sent" do
      estimate.update!(status: :sent)
      get public_estimate_path(token: estimate.token)
      expect(estimate.reload.status).to eq("viewed")
    end

    it "returns 404 for invalid token" do
      get public_estimate_path(token: "invalid_token")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /estimates/:token/approve" do
    it "approves the estimate and creates a booking" do
      patch approve_public_estimate_path(token: estimate.token)
      
      if response.status == 302 && flash[:alert].present?
        fail "Approval failed with error: #{flash[:alert]}"
      end
      
      estimate.reload
      expect(estimate.status).to eq("approved")
      expect(estimate.approved_at).to be_present
      expect(estimate.booking).to be_present
      expect(Booking.count).to eq(1)
    end

    it "creates an invoice for the booking" do
      expect {
        patch approve_public_estimate_path(token: estimate.token)
      }.to change(Invoice, :count).by(1)
    end

    it "redirects to payment when deposit is required" do
      patch approve_public_estimate_path(token: estimate.token)
      estimate.reload
      invoice = estimate.booking.invoice
      expect(response).to redirect_to(new_payment_path(invoice_id: invoice.id))
    end

    context "when no deposit is required" do
      let!(:estimate_no_deposit) do
        est = create(:estimate, business: business, tenant_customer: customer, status: :sent, required_deposit: 0, proposed_start_time: 1.week.from_now, proposed_end_time: 1.week.from_now + 2.hours)
        est.estimate_items.first.update!(service: service) if est.estimate_items.any?
        est
      end

      it "redirects to the estimate page with a notice" do
        patch approve_public_estimate_path(token: estimate_no_deposit.token)
        expect(flash[:notice]).to eq('Estimate approved. No deposit was required.')
        expect(response).to redirect_to(public_estimate_path(token: estimate_no_deposit.token))
      end
    end

    context "when estimate is already declined" do
      before { estimate.update!(status: :declined, declined_at: Time.current) }

      it "does not allow re-approval" do
        patch approve_public_estimate_path(token: estimate.token)
        expect(flash[:alert]).to eq('This estimate cannot be approved.')
        expect(response).to redirect_to(public_estimate_path(token: estimate.token))
      end
    end

    it "sends approval notification email" do
      expect {
        patch approve_public_estimate_path(token: estimate.token)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'estimate_approved', 'deliver_now', hash_including(args: [estimate]))
    end
  end

  describe "PATCH /estimates/:token/decline" do
    it "declines the estimate and sets declined_at" do
      patch decline_public_estimate_path(token: estimate.token)
      estimate.reload
      expect(estimate.status).to eq("declined")
      expect(estimate.declined_at).to be_present
    end

    it "redirects to estimate page with notice" do
      patch decline_public_estimate_path(token: estimate.token)
      expect(response).to redirect_to(public_estimate_path(token: estimate.token))
      expect(flash[:notice]).to eq('You have declined this estimate.')
    end

    it "sends decline notification email" do
      expect {
        patch decline_public_estimate_path(token: estimate.token)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'estimate_declined', 'deliver_now', hash_including(args: [estimate]))
    end
  end

  describe "POST /estimates/:token/request_changes" do
    it "sends a change request notification" do
      expect {
        post request_changes_public_estimate_path(token: estimate.token), params: { changes_request: "Please adjust the pricing" }
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'request_changes_notification', 'deliver_now', hash_including(args: [estimate, "Please adjust the pricing"]))
    end

    it "redirects with success message" do
      post request_changes_public_estimate_path(token: estimate.token), params: { changes_request: "Please adjust the pricing" }
      expect(response).to redirect_to(public_estimate_path(token: estimate.token))
      expect(flash[:notice]).to eq('Your change request has been sent.')
    end

    it "uses default message when none provided" do
      expect {
        post request_changes_public_estimate_path(token: estimate.token)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'request_changes_notification', 'deliver_now', hash_including(args: [estimate, "Customer has requested changes, please review."]))
    end
  end
end 