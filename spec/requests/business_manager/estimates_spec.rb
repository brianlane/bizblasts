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

    context "with labor and part items including save-for-future fields" do
      let(:customer) { create(:tenant_customer, business: business) }
      let(:estimate_params_with_save_fields) {
        {
          tenant_customer_id: customer.id,
          estimate_items_attributes: {
            "0" => {
              item_type: "labor",
              description: "Custom labor work",
              hours: "2.5",
              hourly_rate: "75",
              tax_rate: "8.5",
              optional: "0",
              save_as_service: "1",
              service_type: "standard",
              service_name: "Custom Standard Service"
            },
            "1" => {
              item_type: "part",
              description: "Custom part",
              qty: "3",
              cost_rate: "25.00",
              tax_rate: "8.5",
              optional: "0",
              save_as_product: "1",
              product_type: "standard",
              product_name: "Custom Standard Product"
            }
          }
        }
      }

      it "creates the estimate without raising UnknownAttributeError" do
        expect {
          post business_manager_estimates_path, params: { estimate: estimate_params_with_save_fields }
        }.to change(Estimate, :count).by(1)

        expect(response).to redirect_to(business_manager_estimate_path(Estimate.last))
      end

      it "creates the estimate items correctly" do
        post business_manager_estimates_path, params: { estimate: estimate_params_with_save_fields }

        estimate = Estimate.last
        expect(estimate.estimate_items.count).to eq(2)

        labor_item = estimate.estimate_items.find_by(description: "Custom labor work")
        expect(labor_item).to be_present
        expect(labor_item.hours).to eq(2.5)
        expect(labor_item.hourly_rate).to eq(75)

        part_item = estimate.estimate_items.find_by(description: "Custom part")
        expect(part_item).to be_present
        expect(part_item.qty).to eq(3)
        expect(part_item.cost_rate).to eq(25.00)
      end

      it "creates a service from labor item when save_as_service is checked" do
        expect {
          post business_manager_estimates_path, params: { estimate: estimate_params_with_save_fields }
        }.to change(Service, :count).by(1)

        service = Service.last
        expect(service.name).to eq("Custom Standard Service")
        expect(service.service_type).to eq("standard")
        expect(service.duration).to eq(150) # 2.5 hours * 60 minutes
        expect(service.price).to eq(187.5) # 2.5 * 75

        # Verify the estimate item was converted to service type
        estimate = Estimate.last
        labor_item = estimate.estimate_items.first
        expect(labor_item.item_type).to eq("service")
        expect(labor_item.service_id).to eq(service.id)
      end

      it "creates a product from part item when save_as_product is checked" do
        expect {
          post business_manager_estimates_path, params: { estimate: estimate_params_with_save_fields }
        }.to change(Product, :count).by(1)

        product = Product.last
        expect(product.name).to eq("Custom Standard Product")
        expect(product.product_type).to eq("standard")
        expect(product.price).to eq(25.00)

        # Verify the estimate item was converted to product type
        estimate = Estimate.last
        part_item = estimate.estimate_items.second
        expect(part_item.item_type).to eq("product")
        expect(part_item.product_id).to eq(product.id)
      end

      it "does not create service/product when save flags are not checked" do
        params_without_save = estimate_params_with_save_fields.deep_dup
        params_without_save[:estimate_items_attributes]["0"][:save_as_service] = "0"
        params_without_save[:estimate_items_attributes]["1"][:save_as_product] = "0"

        expect {
          post business_manager_estimates_path, params: { estimate: params_without_save }
        }.to change(Service, :count).by(0)
          .and change(Product, :count).by(0)

        estimate = Estimate.last
        expect(estimate.estimate_items.first.item_type).to eq("labor")
        expect(estimate.estimate_items.second.item_type).to eq("part")
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