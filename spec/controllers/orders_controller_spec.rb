require 'rails_helper'

RSpec.describe Public::OrdersController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let!(:product) { create(:product, business: business) }
  let!(:variant) { create(:product_variant, product: product) }
  let!(:shipping_method) { create(:shipping_method, business: business) }
  let!(:tax_rate) { create(:tax_rate, business: business) }
  let!(:user) { create(:user, email: 'test@example.com') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
    session[:cart] = { variant.id.to_s => 2 }
    # Sign in the user to handle authentication
    sign_in user
  end

  describe 'GET #new' do
    it 'builds order from cart' do
      get :new
      expect(response).to be_successful
      expect(assigns(:order).line_items.size).to eq(1)
    end
  end

  describe 'POST #create' do
    before do
      # Mock the checkout session creation for the redirect
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_test_123')
      })
    end

    it 'creates order and redirects to Stripe Checkout' do
      post :create, params: { order: { shipping_method_id: shipping_method.id, tax_rate_id: tax_rate.id } }
      
      # Should redirect to Stripe instead of the order page
      expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
      expect(session[:cart]).to eq({})
      
      # Verify order was created
      order = Order.last
      expect(order).to be_present
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.invoice).to be_present
      
      # Verify Stripe service was called with correct parameters
      expect(StripeService).to have_received(:create_payment_checkout_session).with(
        invoice: order.invoice,
        success_url: order_url(order, payment_success: true, host: 'testtenant.lvh.me'),
        cancel_url: order_url(order, payment_cancelled: true, host: 'testtenant.lvh.me')
      )
    end

    context 'when Stripe error occurs' do
      before do
        allow(StripeService).to receive(:create_payment_checkout_session)
          .and_raise(Stripe::StripeError.new('Stripe connection error'))
      end

      it 'redirects to order with error message' do
        post :create, params: { order: { shipping_method_id: shipping_method.id, tax_rate_id: tax_rate.id } }
        
        order = Order.last
        expect(response).to redirect_to(order_path(order))
        expect(flash[:alert]).to include('Could not connect to Stripe')
      end
    end
  end
end 