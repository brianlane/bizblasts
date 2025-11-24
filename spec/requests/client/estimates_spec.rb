require 'rails_helper'

RSpec.describe "Client::Estimates", type: :request do
  let(:business) { create(:business) }
  let(:customer_user) { create(:user, :client) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, user: customer_user) }
  let!(:other_customer) { create(:tenant_customer, business: business) }
  let!(:service) { create(:service, business: business) }

  let!(:my_estimate) do
    est = create(:estimate, business: business, tenant_customer: tenant_customer, status: :sent)
    est.estimate_items.first.update!(service: service) if est.estimate_items.any?
    est
  end

  let!(:other_estimate) do
    est = create(:estimate, business: business, tenant_customer: other_customer, status: :sent)
    est.estimate_items.first.update!(service: service) if est.estimate_items.any?
    est
  end

  before do
    host! "#{business.subdomain}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in customer_user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /my-estimates (index)" do
    it "renders a successful response" do
      get client_estimates_path
      expect(response).to be_successful
    end

    it "shows only the current user's estimates" do
      get client_estimates_path
      expect(assigns(:estimates)).to include(my_estimate)
      expect(assigns(:estimates)).not_to include(other_estimate)
    end

    it "orders estimates by created_at descending" do
      older_estimate = create(:estimate, business: business, tenant_customer: tenant_customer, created_at: 1.week.ago)
      get client_estimates_path
      estimates = assigns(:estimates)
      expect(estimates.first).to eq(my_estimate)
    end
  end

  describe "GET /my-estimates/:id (show)" do
    it "renders a successful response for own estimate" do
      get client_estimate_path(my_estimate)
      expect(response).to be_successful
    end

    it "denies access to other customer's estimate" do
      expect {
        get client_estimate_path(other_estimate)
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  context "when not signed in" do
    before { sign_out customer_user }

    it "redirects to sign in for index" do
      get client_estimates_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects to sign in for show" do
      get client_estimate_path(my_estimate)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

