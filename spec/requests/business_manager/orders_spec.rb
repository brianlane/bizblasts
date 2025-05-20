require 'rails_helper'

RSpec.describe "Business Manager Orders", type: :request do
  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) } # Not associated with the business
  let!(:tenant_customer) { create(:tenant_customer, business: business) }
  let!(:shipping_method) { create(:shipping_method, business: business) }
  let!(:tax_rate) { create(:tax_rate, business: business) }
  
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

    describe "GET /manage/orders/new" do
      before { sign_in manager }

      it "renders the new form with necessary collections" do
        get new_business_manager_order_path
        expect(response).to be_successful
        expect(assigns(:order)).to be_a_new(Order)
        expect(assigns(:customers)).to eq([tenant_customer])
        expect(assigns(:shipping_methods)).to eq(business.shipping_methods.active)
        expect(assigns(:tax_rates)).to eq(business.tax_rates)
        expect(assigns(:product_variants)).to all(be_a(ProductVariant))
        expect(assigns(:services)).to all(be_a(Service))
        expect(assigns(:staff_members)).to all(be_a(StaffMember))
      end
    end
    
    describe "POST /manage/orders" do
      before { sign_in manager }

      let(:variant) { create(:product_variant, product: create(:product, business: business), stock_quantity: 10) }

      context "with valid parameters" do
        let(:valid_params) do
          {
            order: {
              tenant_customer_id: tenant_customer.id,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: { '0' => { product_variant_id: variant.id, quantity: 2 } }
            }
          }
        end

        it "creates a new order and redirects to the order show page" do
          expect {
            post business_manager_orders_path, params: valid_params
          }.to change(business.orders, :count).by(1)

          order = business.orders.last
          expect(response).to redirect_to(business_manager_order_path(order))
          expect(order.order_type).to eq('product')
        end
      end

      context "with insufficient stock" do
        let(:low_stock_variant) { create(:product_variant, product: create(:product, business: business), stock_quantity: 1) }
        let(:invalid_params) do
          {
            order: {
              tenant_customer_id: tenant_customer.id,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: { '0' => { product_variant_id: low_stock_variant.id, quantity: 5 } }
            }
          }
        end

        it "does not create an order and renders :new with errors" do
          expect {
            post business_manager_orders_path, params: invalid_params
          }.not_to change(business.orders, :count)

          expect(response).to render_template(:new)
          expect(flash[:alert]).to include("Line items quantity for #{low_stock_variant.name} is not sufficient. Only #{low_stock_variant.stock_quantity} available.")
        end
      end

      context "with new nested customer" do
        let(:customer_attrs) { { name: 'New Cust', email: 'new@cust.com', phone: '555-0000' } }
        let(:nested_params) do
          {
            order: {
              tenant_customer_id: 'new',
              tenant_customer_attributes: customer_attrs,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: { '0' => { product_variant_id: variant.id, quantity: 2 } }
            }
          }
        end

        it "creates a new customer and order" do
          expect {
            post business_manager_orders_path, params: nested_params
          }.to change(business.tenant_customers, :count).by(1).and change(business.orders, :count).by(1)

          order = business.orders.last
          expect(order.tenant_customer.email).to eq('new@cust.com')
          expect(order.order_type).to eq('product')
        end
      end

      context "with service-only line items" do
        let(:service_obj) { create(:service, business: business) }
        let(:staff_member) { create(:staff_member, business: business) }
        let(:service_params) do
          {
            order: {
              tenant_customer_id: tenant_customer.id,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: { '0' => { service_id: service_obj.id, staff_member_id: staff_member.id, quantity: 1, price: 200.0, total_amount: 200.0 } }
            }
          }
        end

        it "creates a service order" do
          expect {
            post business_manager_orders_path, params: service_params
          }.to change(business.orders, :count).by(1)

          order = business.orders.last
          expect(order.order_type).to eq('service')
          expect(order.line_items.first.service_id).to eq(service_obj.id)
        end
      end

      context "with mixed line items" do
        let(:service_obj2) { create(:service, business: business) }
        let(:staff_member2) { create(:staff_member, business: business) }
        let(:mixed_params) do
          {
            order: {
              tenant_customer_id: tenant_customer.id,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: {
                '0' => { product_variant_id: variant.id, quantity: 1 },
                '1' => { service_id: service_obj2.id, staff_member_id: staff_member2.id, quantity: 1, price: 150.0, total_amount: 150.0 }
              }
            }
          }
        end

        it "creates a mixed order" do
          expect {
            post business_manager_orders_path, params: mixed_params
          }.to change(business.orders, :count).by(1)

          order = business.orders.last
          expect(order.order_type).to eq('mixed')
        end
      end
    end
    
    describe "GET /manage/orders/:id/edit" do
      before { sign_in manager }
      let!(:order) { create(:order, tenant_customer: tenant_customer, business: business, order_type: :product, line_items_count: 1) }

      it "renders the edit form and loads collections" do
        get edit_business_manager_order_path(order)
        expect(response).to be_successful
        expect(assigns(:order)).to eq(order)
        expect(assigns(:customers)).to eq([tenant_customer])
        expect(assigns(:shipping_methods)).to eq(business.shipping_methods.active)
        expect(assigns(:tax_rates)).to eq(business.tax_rates)
        expect(assigns(:product_variants)).to all(be_a(ProductVariant))
        expect(assigns(:services)).to all(be_a(Service))
        expect(assigns(:staff_members)).to all(be_a(StaffMember))
      end
    end
    
    describe "PATCH /manage/orders/:id" do
      before { sign_in manager }
      let!(:order) { create(:order, tenant_customer: tenant_customer, business: business, order_type: :product, line_items_count: 1) }
      let(:variant2) { create(:product_variant, product: create(:product, business: business), stock_quantity: 10) }

      context "with valid parameters" do
        let(:update_params) do
          {
            id: order.id,
            order: {
              tenant_customer_id: tenant_customer.id,
              shipping_method_id: shipping_method.id,
              tax_rate_id: tax_rate.id,
              line_items_attributes: { order.line_items.first.id.to_s => { id: order.line_items.first.id, product_variant_id: variant2.id, quantity: 3 } }
            }
          }
        end

        it "updates the order and redirects to show" do
          patch business_manager_order_path(order), params: update_params
          expect(response).to redirect_to(business_manager_order_path(order))

          order.reload
          expect(order.line_items.first.product_variant_id).to eq(variant2.id)
          expect(order.line_items.first.quantity).to eq(3)
          expect(order.order_type).to eq('product')
        end
      end

      context "with insufficient stock" do
        let(:low_stock_variant2) { create(:product_variant, product: create(:product, business: business), stock_quantity: 1) }
        let(:invalid_update_params) do
          {
            id: order.id,
            order: { line_items_attributes: { order.line_items.first.id.to_s => { id: order.line_items.first.id, product_variant_id: low_stock_variant2.id, quantity: 5 } } }
          }
        end

        it "does not update and re-renders :edit with errors" do
          patch business_manager_order_path(order), params: invalid_update_params
          expect(response).to render_template(:edit)
          expect(flash[:alert]).to include("Line items quantity for #{low_stock_variant2.name} is not sufficient. Only #{low_stock_variant2.stock_quantity} available.")
        end
      end
    end
  end
end 