require 'rails_helper'

RSpec.describe "Public::Estimates", type: :request do
  let(:business) { create(:business, stripe_account_id: 'acct_test_123') }
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
    let(:signature_params) do
      {
        signature_data: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        signature_name: 'Test Customer'
      }
    end

    let(:mock_booking) { create(:booking, business: business, tenant_customer: customer, service: service, staff_member: staff_member, start_time: estimate.proposed_start_time, end_time: estimate.proposed_end_time) }
    let(:mock_invoice) { create(:invoice, business: business, tenant_customer: customer, booking: mock_booking, amount: estimate.required_deposit, tax_amount: 0, total_amount: estimate.required_deposit) }
    let(:mock_checkout_session) do
      double('Stripe::Checkout::Session',
             id: 'cs_test_123',
             payment_intent: 'pi_test_123',
             url: 'https://checkout.stripe.com/pay/cs_test_123')
    end

    let(:signature_service) { instance_double(ClientDocuments::SignatureService, capture!: true) }
    let(:workflow_service) { instance_double(ClientDocuments::WorkflowService, mark_signature_captured!: true, mark_pending_signature!: true) }
    let(:deposit_service) { instance_double(ClientDocuments::DepositService, initiate_checkout!: { session: mock_checkout_session }) }

    before do
      # Mock external services
      allow(EstimatePdfGenerator).to receive(:new).and_return(double(generate: true))
      allow(EstimateToBookingService).to receive(:new).and_return(double(call: mock_booking))
      allow(mock_booking).to receive(:reload).and_return(mock_booking)
      allow(mock_booking).to receive(:invoice).and_return(mock_invoice)
      allow(ClientDocuments::SignatureService).to receive(:new).and_return(signature_service)
      allow(ClientDocuments::WorkflowService).to receive(:new).and_return(workflow_service)
      allow(ClientDocuments::DepositService).to receive(:new).and_return(deposit_service)
    end

    it "approves the estimate and creates a booking" do
      patch approve_public_estimate_path(token: estimate.token), params: signature_params

      if response.status == 302 && flash[:alert].present?
        fail "Approval failed with error: #{flash[:alert]}"
      end

      estimate.reload
      expect(estimate.status).to eq("pending_payment")
      expect(estimate.signed_at).to be_present
      expect(estimate.signature_data).to be_present
      expect(estimate.signature_name).to eq('Test Customer')
    end

    it "calls EstimateToBookingService to create booking" do
      expect(EstimateToBookingService).to receive(:new).and_return(double(call: mock_booking))
      patch approve_public_estimate_path(token: estimate.token), params: signature_params
      expect(response).to redirect_to(mock_checkout_session.url)
    end

    it "redirects to Stripe checkout when deposit is required" do
      patch approve_public_estimate_path(token: estimate.token), params: signature_params
      estimate.reload
      expect(estimate.status).to eq("pending_payment")
      expect(response).to redirect_to(mock_checkout_session.url)
    end

    context "when no deposit is required" do
      let!(:estimate_no_deposit) do
        est = create(:estimate, business: business, tenant_customer: customer, status: :sent, required_deposit: 0, proposed_start_time: 1.week.from_now, proposed_end_time: 1.week.from_now + 2.hours)
        est.estimate_items.first.update!(service: service) if est.estimate_items.any?
        est
      end

      it "redirects to Stripe checkout for full invoice" do
        patch approve_public_estimate_path(token: estimate_no_deposit.token), params: signature_params
        estimate_no_deposit.reload
        expect(estimate_no_deposit.status).to eq("pending_payment")
        expect(response).to redirect_to(mock_checkout_session.url)
      end
    end

    context "when estimate is already declined" do
      before { estimate.update!(status: :declined, declined_at: Time.current) }

      it "does not allow re-approval" do
        patch approve_public_estimate_path(token: estimate.token), params: signature_params
        expect(flash[:alert]).to eq('This estimate cannot be approved at this time.')
        expect(response).to redirect_to(public_estimate_path(token: estimate.token))
      end
    end

    it "prevents duplicate approvals from concurrent requests" do
      # Simulate concurrent requests by attempting to approve twice

      # First approval should succeed
      patch approve_public_estimate_path(token: estimate.token), params: signature_params
      estimate.reload
      expect(estimate.status).to eq("pending_payment")

      # Second approval attempt should be rejected (no longer in sent/viewed status)
      patch approve_public_estimate_path(token: estimate.token), params: signature_params

      # Should redirect back with error
      expect(flash[:alert]).to eq('This estimate cannot be approved at this time.')
      expect(response).to redirect_to(public_estimate_path(token: estimate.token))
    end

    it "calls ClientDocuments::DepositService to initiate checkout session" do
      expect(ClientDocuments::DepositService).to receive(:new).and_return(deposit_service)
      patch approve_public_estimate_path(token: estimate.token), params: signature_params
      expect(response).to redirect_to(mock_checkout_session.url)
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