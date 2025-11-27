require 'rails_helper'

RSpec.describe "/business_manager/estimates", type: :request do
  let(:business) { create(:business) }
  let(:manager) { create(:user, :manager, business: business) }

  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in manager
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  let(:valid_attributes) {
    attributes_for(:estimate).merge(tenant_customer_id: create(:tenant_customer, business: business).id)
  }

  let(:invalid_attributes) {
    # When tenant_customer_id is nil, contact fields are required
    { tenant_customer_id: nil, first_name: '', last_name: '', email: '', phone: '', address: '', city: '', state: '', zip: '' }
  }

  describe "GET /index" do
    it "renders a successful response" do
      create(:estimate, business: business)
      get business_manager_estimates_path
      expect(response).to be_successful
    end
  end

  describe "GET /show" do
    it "renders a successful response" do
      estimate = create(:estimate, business: business)
      get business_manager_estimate_path(estimate)
      expect(response).to be_successful
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_business_manager_estimate_path
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      estimate = create(:estimate, business: business)
      get edit_business_manager_estimate_path(estimate)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new Estimate" do
        expect {
          post business_manager_estimates_path, params: { estimate: valid_attributes }
        }.to change(Estimate, :count).by(1)
      end

      it "redirects to the created estimate" do
        post business_manager_estimates_path, params: { estimate: valid_attributes }
        expect(response).to redirect_to(business_manager_estimate_path(Estimate.last))
      end
    end

    context "with invalid parameters" do
      it "does not create a new Estimate" do
        expect {
          post business_manager_estimates_path, params: { estimate: invalid_attributes.merge(tenant_customer_id: 'new', tenant_customer_attributes: { first_name: ''}) }
        }.to change(Estimate, :count).by(0)
      end

      it "renders a successful response (i.e. to display the 'new' template)" do
        post business_manager_estimates_path, params: { estimate: invalid_attributes.merge(tenant_customer_id: 'new', tenant_customer_attributes: { first_name: ''}) }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    let(:estimate) { create(:estimate, business: business) }

    context "with valid parameters" do
      let(:new_attributes) { { internal_notes: "These are updated notes" } }

      it "updates the requested estimate" do
        patch business_manager_estimate_path(estimate), params: { estimate: new_attributes }
        estimate.reload
        expect(estimate.internal_notes).to eq("These are updated notes")
      end

      it "redirects to the estimate" do
        patch business_manager_estimate_path(estimate), params: { estimate: new_attributes }
        estimate.reload
        expect(response).to redirect_to(business_manager_estimate_path(estimate))
      end
    end

    context "with invalid parameters" do
      it "renders a successful response (i.e. to display the 'edit' template)" do
        patch business_manager_estimate_path(estimate), params: { estimate: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested estimate" do
      estimate = create(:estimate, business: business)
      expect {
        delete business_manager_estimate_path(estimate)
      }.to change(Estimate, :count).by(-1)
    end

    it "redirects to the estimates list" do
      estimate = create(:estimate, business: business)
      delete business_manager_estimate_path(estimate)
      expect(response).to redirect_to(business_manager_estimates_path)
    end
  end

  describe "POST /send_to_customer" do
    it "sends the estimate and redirects" do
      customer = create(:tenant_customer, business: business, email: 'customer@example.com')
      estimate = create(:estimate, business: business, tenant_customer: customer)
      
      expect {
        patch send_to_customer_business_manager_estimate_path(estimate)
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with('EstimateMailer', 'send_estimate', 'deliver_now', args: [estimate])
      
      estimate.reload
      expect(response).to redirect_to(business_manager_estimate_path(estimate))
      expect(flash[:notice]).to eq('Estimate sent to customer successfully.')
    end
  end
end 