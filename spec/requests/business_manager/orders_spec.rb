require 'rails_helper'

RSpec.describe "Business Manager Orders", type: :request do
  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) } # Not associated with the business
  let!(:tenant_customer) { create(:tenant_customer, business: business) }
  
  # Create different types of orders
  let!(:product_order) { create(:order, business: business, tenant_customer: tenant_customer, order_type: :product, line_items_count: 2) }
  let!(:service_order) { create(:order, business: business, tenant_customer: tenant_customer, order_type: :service, line_items_count: 1) }
  let!(:mixed_order) { create(:order, business: business, tenant_customer: tenant_customer, order_type: :mixed, line_items_count: 3) }

  before do
    # Set the host to the business's hostname for tenant scoping
    host! "#{business.hostname}.lvh.me"
    # Use ActsAsTenant here as the BaseController would
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "Authorization" do
    context "when not signed in" do
      it "redirects GET /manage/orders to login" do
        get business_manager_orders_path
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects GET /manage/orders/:id to login" do
        get business_manager_order_path(product_order)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in as a client" do
      before { sign_in client }

      it "redirects GET /manage/orders" do
        get business_manager_orders_path
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end

      it "redirects GET /manage/orders/:id" do
        get business_manager_order_path(product_order)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include("access this area")
      end
    end
  end

  describe "Manager/Staff Access" do
    before { sign_in manager } # Can also test with staff

    describe "GET /manage/orders" do
      it "is successful" do
        get business_manager_orders_path
        expect(response).to be_successful
      end

      it "assigns orders belonging to the current business" do
        other_business = create(:business)
        other_order = nil
        ActsAsTenant.with_tenant(other_business) do
          other_order = create(:order, business: other_business)
        end
        
        get business_manager_orders_path
        expect(assigns(:orders)).to include(product_order, service_order, mixed_order)
        expect(assigns(:orders)).not_to include(other_order)
      end

      context "with status filter" do
        it "filters orders by status" do
          pending_order = create(:order, :pending, business: business, tenant_customer: tenant_customer)
          completed_order = create(:order, :completed, business: business, tenant_customer: tenant_customer)
          
          get business_manager_orders_path, params: { status: 'pending' }
          expect(assigns(:orders)).to include(pending_order)
          expect(assigns(:orders)).not_to include(completed_order)
          expect(assigns(:status_filter)).to eq('pending')
        end
      end

      context "with type filter" do
        it "filters orders by type" do
          get business_manager_orders_path, params: { type: 'product' }
          expect(assigns(:orders)).to include(product_order)
          expect(assigns(:orders)).not_to include(service_order, mixed_order)
          expect(assigns(:type_filter)).to eq('product')
        end

        it "filters orders by service type" do
          get business_manager_orders_path, params: { type: 'service' }
          expect(assigns(:orders)).to include(service_order)
          expect(assigns(:orders)).not_to include(product_order, mixed_order)
          expect(assigns(:type_filter)).to eq('service')
        end

        it "filters orders by mixed type" do
          get business_manager_orders_path, params: { type: 'mixed' }
          expect(assigns(:orders)).to include(mixed_order)
          expect(assigns(:orders)).not_to include(product_order, service_order)
          expect(assigns(:type_filter)).to eq('mixed')
        end
      end

      context "with combined filters" do
        it "applies both status and type filters" do
          pending_product_order = create(:order, :pending, business: business, tenant_customer: tenant_customer, order_type: :product)
          completed_product_order = create(:order, :completed, business: business, tenant_customer: tenant_customer, order_type: :product)
          
          get business_manager_orders_path, params: { status: 'pending', type: 'product' }
          expect(assigns(:orders)).to include(pending_product_order)
          expect(assigns(:orders)).not_to include(completed_product_order, service_order, mixed_order)
          expect(assigns(:status_filter)).to eq('pending')
          expect(assigns(:type_filter)).to eq('product')
        end
      end
    end

    describe "GET /manage/orders/:id" do
      it "is successful" do
        get business_manager_order_path(product_order)
        expect(response).to be_successful
      end

      it "assigns the correct order" do
        get business_manager_order_path(product_order)
        expect(assigns(:order)).to eq(product_order)
      end

      it "includes line items and their products in the query" do
        # This tests that the eager loading works properly
        expect_any_instance_of(ActiveRecord::Relation).to receive(:includes).with(
          hash_including(line_items: { product_variant: :product })
        ).and_call_original
        
        get business_manager_order_path(product_order)
      end
    end
  end
end 