require 'rails_helper'

RSpec.describe BusinessManager::OrdersController, type: :controller do
  let(:business)        { create(:business) }
  let(:manager)         { create(:user, :manager, business: business) }
  let(:shipping_method) { create(:shipping_method, business: business) }
  let(:tax_rate)        { create(:tax_rate, business: business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:product)         { create(:product, business: business) }
  let(:variant)         { create(:product_variant, product: product, stock_quantity: 10) }

  before do
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in manager
  end

  describe 'GET #new' do
    it 'assigns a new order and loads collections' do
      get :new
      expect(response).to be_successful
      expect(assigns(:order)).to be_a_new(Order)
      expect(assigns(:customers)).to eq(business.tenant_customers.active)
      expect(assigns(:shipping_methods)).to eq(business.shipping_methods.active)
      expect(assigns(:tax_rates)).to eq(business.tax_rates)
      expect(assigns(:product_variants)).to all(be_a(ProductVariant))
      expect(assigns(:services)).to all(be_a(Service))
      expect(assigns(:staff_members)).to all(be_a(StaffMember))
      expect(response).to render_template(:new)
    end
  end

  describe 'POST #create' do
    context 'with valid params and existing customer' do
      let(:valid_params) do
        {
          order: {
            tenant_customer_id: tenant_customer.id,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: {
              '0' => { product_variant_id: variant.id, quantity: 2 }
            }
          }
        }
      end

      it 'creates the order and redirects' do
        expect {
          post :create, params: valid_params
        }.to change(business.orders, :count).by(1)

        order = business.orders.last
        expect(order.order_type).to eq('product')
        expect(response).to redirect_to(business_manager_order_path(order))
        expect(flash[:notice]).to eq('Order created successfully')
      end
      
      it 'provides invoice creation feedback for service orders' do
        service = create(:service, business: business)
        staff_member = create(:staff_member, business: business)
        
        service_params = {
          order: {
            tenant_customer_id: tenant_customer.id,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: {
              '0' => { 
                service_id: service.id, 
                staff_member_id: staff_member.id,
                quantity: 1,
                price: 100.0,
                total_amount: 100.0
              }
            }
          }
        }
        
        expect {
          post :create, params: service_params
        }.to change(business.orders, :count).by(1)
         .and change(Invoice, :count).by(1)

        order = business.orders.last
        expect(order.order_type).to eq('service')
        expect(order.invoice).to be_present
        expect(response).to redirect_to(business_manager_order_path(order))
        expect(flash[:notice]).to eq('Order created successfully. Invoice has been generated and emailed to the customer.')
      end
    end

    context 'with quantity exceeding stock' do
      let(:low_stock_variant) { create(:product_variant, product: product, stock_quantity: 1) }
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

      it 'does not create the order and renders new with errors' do
        expect {
          post :create, params: invalid_params
        }.not_to change(business.orders, :count)

        expect(response).to render_template(:new)
        expect(flash[:alert]).to include("Line items quantity for #{low_stock_variant.name} is not sufficient. Only #{low_stock_variant.stock_quantity} available.")
      end
    end

    context 'with new nested customer' do
      let(:customer_attrs) { { first_name: 'New', last_name: 'Customer', email: 'new@example.com', phone: '555-1234' } }
      let(:nested_params) do
        {
          order: {
            tenant_customer_id: 'new',
            tenant_customer_attributes: customer_attrs,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: { '0' => { product_variant_id: variant.id, quantity: 3 } }
          }
        }
      end

      it 'creates a new tenant_customer and order' do
        expect {
          post :create, params: nested_params
        }.to change(business.tenant_customers, :count).by(1).and change(business.orders, :count).by(1)

        order = business.orders.last
        expect(order.tenant_customer.full_name).to eq('New Customer')
        expect(order.order_type).to eq('product')
        expect(response).to redirect_to(business_manager_order_path(order))
      end
    end

    context 'with service-only line items' do
      let(:service_obj) { create(:service, business: business) }
      let(:staff_member) { create(:staff_member, business: business) }
      let(:service_params) do
        {
          order: {
            tenant_customer_id: tenant_customer.id,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: { '0' => { service_id: service_obj.id, staff_member_id: staff_member.id, quantity: 1, price: 100.0, total_amount: 100.0 } }
          }
        }
      end

      it 'creates a service order' do
        expect {
          post :create, params: service_params
        }.to change(business.orders, :count).by(1)

        order = business.orders.last
        expect(order.order_type).to eq('service')
        expect(order.line_items.first.service_id).to eq(service_obj.id)
        expect(response).to redirect_to(business_manager_order_path(order))
      end
    end

    context 'with mixed line items' do
      let(:service_obj2) { create(:service, business: business) }
      let(:staff_member2) { create(:staff_member, business: business) }
      let(:mixed_params) do
        {
          order: {
            tenant_customer_id: tenant_customer.id,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: {
              '0' => { product_variant_id: variant.id, quantity: 2 },
              '1' => { service_id: service_obj2.id, staff_member_id: staff_member2.id, quantity: 1, price: 50.0, total_amount: 50.0 }
            }
          }
        }
      end

      it 'creates a mixed order' do
        expect {
          post :create, params: mixed_params
        }.to change(business.orders, :count).by(1)

        order = business.orders.last
        expect(order.order_type).to eq('mixed')
        expect(order.line_items.map(&:service_id)).to include(service_obj2.id)
        expect(order.line_items.map(&:product_variant_id)).to include(variant.id)
        expect(response).to redirect_to(business_manager_order_path(order))
      end
    end
  end

  describe 'GET #edit' do
    let!(:order) { create(:order, tenant_customer: tenant_customer, business: business, order_type: :product) }
    let!(:line_item) { create(:line_item, lineable: order, product_variant: variant) }

    it 'assigns the order and loads collections' do
      get :edit, params: { id: order.id }
      expect(response).to be_successful
      expect(assigns(:order)).to eq(order)
      expect(assigns(:customers)).to eq(business.tenant_customers.active)
      expect(assigns(:shipping_methods)).to eq(business.shipping_methods.active)
      expect(assigns(:tax_rates)).to eq(business.tax_rates)
      expect(assigns(:product_variants)).to all(be_a(ProductVariant))
      expect(assigns(:services)).to all(be_a(Service))
      expect(assigns(:staff_members)).to all(be_a(StaffMember))
      expect(response).to render_template(:edit)
    end
  end

  describe 'PATCH #update' do
    let!(:order) { create(:order, tenant_customer: tenant_customer, business: business, order_type: :product) }
    let!(:line_item) { create(:line_item, lineable: order, product_variant: variant, quantity: 2) }

    context 'with valid params' do
      let(:update_params) do
        {
          id: order.id,
          order: {
            tenant_customer_id: tenant_customer.id,
            shipping_method_id: shipping_method.id,
            tax_rate_id: tax_rate.id,
            line_items_attributes: { line_item.id.to_s => { id: line_item.id, product_variant_id: variant.id, quantity: 3 } }
          }
        }
      end

      it 'updates the order and redirects' do
        patch :update, params: update_params
        expect(response).to redirect_to(business_manager_order_path(order))

        order.reload
        expect(order.line_items.first.quantity).to eq(3)
        expect(flash[:notice]).to eq('Order updated successfully')
      end
    end

    context 'with quantity exceeding stock' do
      let(:low_stock_variant) { create(:product_variant, product: product, stock_quantity: 1) }
      let(:invalid_update_params) do
        {
          id: order.id,
          order: {
            tenant_customer_id: tenant_customer.id,
            line_items_attributes: { line_item.id.to_s => { id: line_item.id, product_variant_id: low_stock_variant.id, quantity: 5 } }
          }
        }
      end

      it 'does not update the order and renders edit with errors' do
        patch :update, params: invalid_update_params
        expect(response).to render_template(:edit)
        expect(flash[:alert]).to include("Line items quantity for #{low_stock_variant.name} is not sufficient. Only #{low_stock_variant.stock_quantity} available.")
      end
    end
  end
end 