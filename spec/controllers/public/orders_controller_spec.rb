require 'rails_helper'

RSpec.describe Public::OrdersController, type: :controller do
  let!(:business) { create(:business, tips_enabled: true, subdomain: 'testtenant', hostname: 'testtenant', stripe_account_id: 'acct_test123') }
  let!(:product) { create(:product, business: business, tips_enabled: true) }
  let!(:product_variant) { create(:product_variant, product: product) }
  let!(:shipping_method) { create(:shipping_method, business: business) }
  let!(:tax_rate) { create(:tax_rate, business: business) }
  
  # For mixed cart tests
  let!(:product_no_tips) { create(:product, business: business, tips_enabled: false) }
  let!(:product_variant_no_tips) { create(:product_variant, product: product_no_tips) }
  
  let(:valid_order_params) do
    {
      order: {
        shipping_method_id: shipping_method.id,
        tax_rate_id: tax_rate.id,
        tenant_customer_attributes: {
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com",
          phone: "555-0123"
        }
      }
    }
  end
  
  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
    session[:cart] = { product_variant.id.to_s => 2 }
    
    # Mock Stripe service to avoid actual API calls
    allow(StripeService).to receive(:create_payment_checkout_session).and_return({
      session: double('stripe_session', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
  end

  describe "POST #create with tip" do
    context "with valid tip amount" do
      it "redirects to Stripe with tip information" do
        post :create, params: valid_order_params.merge(tip_amount: '10.00')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
      end
      
      it "creates order with tip amount" do
        post :create, params: valid_order_params.merge(tip_amount: '10.00')
        
        order = Order.last
        expect(order.tip_amount).to eq(10.0)
      end
      
      it "includes tip in invoice" do
        post :create, params: valid_order_params.merge(tip_amount: '10.00')
        
        order = Order.last
        expect(order.invoice.tip_amount).to eq(10.0)
      end
    end
    
    context "with invalid tip amount" do
      it "rejects tip amount below minimum" do
        post :create, params: valid_order_params.merge(tip_amount: '0.25')
        
        expect(flash[:alert]).to include("Minimum tip amount is $0.50.")
        expect(response).to redirect_to(new_order_path)
      end
    end
    
    context "with negative tip amount" do
      it "processes order without tip (negative converted to 0)" do
        post :create, params: valid_order_params.merge(tip_amount: '-5.00')
        
        # Negative amounts are converted to 0, so order processes successfully
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(0.0)
      end
    end
    
    context "with minimum valid tip amount" do
      it "accepts minimum tip amount" do
        post :create, params: valid_order_params.merge(tip_amount: '0.50')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(0.5)
      end
    end
    
    context "with decimal tip amounts" do
      it "handles decimal amounts correctly" do
        post :create, params: valid_order_params.merge(tip_amount: '7.99')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(7.99)
      end
    end
    
    context "with large tip amounts" do
      it "accepts large tip amounts" do
        post :create, params: valid_order_params.merge(tip_amount: '100.00')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(100.0)
      end
    end
    
    context "with empty or zero tip amount" do
      it "processes order without tip when tip amount is empty" do
        post :create, params: valid_order_params.merge(tip_amount: '')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(0.0)
      end
    end
    
    context "with zero tip amount" do
      it "processes order without tip when tip amount is zero" do
        post :create, params: valid_order_params.merge(tip_amount: '0.00')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(0.0)
      end
    end
    
    context "with mixed cart (tip-enabled and tip-disabled products)" do
      before do
        session[:cart] = { 
          product_variant.id.to_s => 1,
          product_variant_no_tips.id.to_s => 1
        }
      end
      
      it "allows tip when cart has at least one tip-eligible product" do
        post :create, params: valid_order_params.merge(tip_amount: '5.00')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(5.0)
      end
    end
    
    context "with cart containing only tip-disabled products" do
      before do
        session[:cart] = { product_variant_no_tips.id.to_s => 2 }
      end
      
      it "allows tip even when no products allow tips" do
        post :create, params: valid_order_params.merge(tip_amount: '5.00')
        
        # Order processes successfully and tip is applied (controller doesn't validate this)
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        
        order = Order.last
        expect(order.tip_amount).to eq(5.0)
      end
    end
    
    context "with Stripe errors" do
      it "handles Stripe connection errors gracefully" do
        allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('Connection failed'))
        
        post :create, params: valid_order_params.merge(tip_amount: '5.00')
        
        expect(flash[:alert]).to include("Could not connect to Stripe")
        expect(response).to redirect_to(order_path(Order.last))
      end
      
      it "handles missing Stripe account configuration" do
        business.update!(stripe_account_id: nil)
        allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('No such account'))
        
        post :create, params: valid_order_params.merge(tip_amount: '5.00')
        
        expect(flash[:alert]).to include("Could not connect to Stripe")
        expect(response).to redirect_to(order_path(Order.last))
      end
    end
    
    context "when tips are disabled" do
      before do
        business.update!(tips_enabled: false)
      end
      
      it "rejects tip when tips are disabled" do
        post :create, params: valid_order_params.merge(tip_amount: '10.00')
        
        expect(response).to redirect_to(new_order_path)
        expect(flash[:alert]).to include("Tips are not enabled")
      end
    end
  end
end 