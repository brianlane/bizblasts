require 'rails_helper'

RSpec.describe "Business Manager Customers", type: :request do
  let!(:business) { create(:business) }
  let!(:manager)  { create(:user, :manager, business: business) }
  let!(:staff)    { create(:user, :staff, business: business) }
  let!(:client)   { create(:user, :client) }
  let!(:other_business) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "Authorization" do
    context "when not signed in" do
      it "redirects GET /manage/customers to login" do
        get business_manager_customers_path
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects GET /manage/customers/:id to login" do
        get business_manager_customer_path(customer)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as a client" do
      before { sign_in client }

      it "redirects GET /manage/customers to dashboard" do
        get business_manager_customers_path
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end
    end
  end

  describe "Manager/Staff Access" do
    before { sign_in manager }

    describe "GET /manage/customers" do
      it "is successful" do
        get business_manager_customers_path
        expect(response).to be_successful
      end

      it "assigns only customers belonging to current business" do
        other_customer = nil
        ActsAsTenant.with_tenant(other_business) do
          other_customer = create(:tenant_customer, business: other_business)
        end
        get business_manager_customers_path
        expect(assigns(:customers)).to include(customer)
        expect(assigns(:customers)).not_to include(other_customer)
      end
    end

    describe "GET /manage/customers/:id" do
      it "is successful" do
        get business_manager_customer_path(customer)
        expect(response).to be_successful
      end

      it "assigns the requested customer" do
        get business_manager_customer_path(customer)
        expect(assigns(:customer)).to eq(customer)
      end
    end

    describe "GET /manage/customers/new" do
      it "renders the new template" do
        get new_business_manager_customer_path
        expect(response).to be_successful
      end
    end

    describe "POST /manage/customers" do
      let(:valid_params) { { tenant_customer: attributes_for(:tenant_customer, email: 'unique@example.com') } }
      let(:invalid_params) { { tenant_customer: { first_name: '', last_name: '', email: 'bad', phone: '' } } }

      it "creates a new customer with valid parameters" do
        expect {
          post business_manager_customers_path, params: valid_params
        }.to change(business.tenant_customers, :count).by(1)
        expect(response).to redirect_to(business_manager_customers_path)
        expect(flash[:notice]).to be_present
      end

      it "does not create with invalid parameters" do
        expect {
          post business_manager_customers_path, params: invalid_params
        }.not_to change(business.tenant_customers, :count)
        expect(response).to be_successful
        expect(response.body).to include("prohibited this customer from being saved")
      end
    end

    describe "GET /manage/customers/:id/edit" do
      it "renders the edit template" do
        get edit_business_manager_customer_path(customer)
        expect(response).to be_successful
      end
    end

    describe "PATCH /manage/customers/:id" do
      let(:update_params) { { tenant_customer: { first_name: 'New', last_name: 'Name' } } }

      it "updates customer with valid data" do
        patch business_manager_customer_path(customer), params: update_params
        expect(response).to redirect_to(business_manager_customer_path(customer))
        expect(customer.reload.full_name).to eq('New Name')
      end

      it "does not update with invalid data" do
        patch business_manager_customer_path(customer), params: { tenant_customer: { email: 'invalid' } }
        expect(response).to be_successful
        expect(response.body).to include("prohibited this customer from being saved")
      end
    end

    describe "DELETE /manage/customers/:id" do
      it "deletes the customer record" do
        cust = create(:tenant_customer, business: business)
        expect {
          delete business_manager_customer_path(cust)
        }.to change(business.tenant_customers, :count).by(-1)
        expect(response).to redirect_to(business_manager_customers_path)
        expect(flash[:notice]).to be_present
      end
    end
  end
end 