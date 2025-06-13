require 'rails_helper'

RSpec.describe Public::InvoicesController, type: :controller do
  let!(:business) { create(:business, tips_enabled: true, subdomain: 'testtenant', hostname: 'testtenant', stripe_account_id: 'acct_test123') }
  let!(:tenant_customer) { create(:tenant_customer, business: business) }
  let!(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
  let!(:invoice) { create(:invoice, business: business, order: order, tenant_customer: tenant_customer, status: :pending) }
  
  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
    
    # Mock Stripe service to avoid actual API calls
    allow(StripeService).to receive(:create_payment_checkout_session).and_return({
      session: double('stripe_session', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
  end

  describe "POST #pay with tip" do
    context "with valid tip amount" do
      it "updates invoice with tip amount" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '5.00' }
        
        expect(invoice.reload.tip_amount).to eq(5.0)
      end
      
      it "redirects to Stripe with tip information" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '5.00' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
      end
    end
    
    context "with invalid tip amount" do
      it "rejects tip amount below minimum" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '0.25' }
        
        expect(flash[:alert]).to include("Minimum tip amount is $0.50.")
        expect(response).to redirect_to(tenant_invoice_path(invoice, access_token: invoice.guest_access_token))
      end
    end
    
    context "with minimum valid tip amount" do
      it "accepts minimum tip amount" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '0.50' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(0.5)
      end
    end
    
    context "with decimal tip amounts" do
      it "handles decimal amounts correctly" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '7.99' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(7.99)
      end
    end
    
    context "with large tip amounts" do
      it "accepts large tip amounts" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '100.00' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(100.0)
      end
    end
    
    context "with negative tip amount" do
      it "processes payment without tip (negative converted to 0)" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '-5.00' }
        
        # Negative amounts are converted to 0, so payment processes successfully
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(0.0)
      end
    end
    
    context "with empty tip amount" do
      it "processes payment without tip when tip amount is empty" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(0.0)
      end
    end
    
    context "with zero tip amount" do
      it "processes payment without tip when tip amount is zero" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '0.00' }
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(invoice.reload.tip_amount).to eq(0.0)
      end
    end
    
    context "with Stripe errors" do
      it "handles Stripe connection errors gracefully" do
        allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('Connection failed'))
        
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '5.00' }
        
        expect(flash[:alert]).to include("Could not connect to Stripe")
        expect(response).to redirect_to(tenant_invoice_path(invoice, access_token: invoice.guest_access_token))
      end
      
      it "handles missing Stripe account configuration" do
        business.update!(stripe_account_id: nil)
        allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('No such account'))
        
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '5.00' }
        
        expect(flash[:alert]).to include("Could not connect to Stripe")
        expect(response).to redirect_to(tenant_invoice_path(invoice, access_token: invoice.guest_access_token))
      end
    end
    
    context "with invalid access token" do
      it "returns 404 for invalid token" do
        expect {
          post :pay, params: { id: invoice.id, access_token: 'invalid_token', tip_amount: '5.00' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
    
    context "with non-existent invoice" do
      it "returns 404 for non-existent invoice" do
        expect {
          post :pay, params: { id: 99999, access_token: 'any_token', tip_amount: '5.00' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
    
    context "when invoice is already paid" do
      before do
        invoice.update!(status: :paid)
      end
      
      it "redirects with notice" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '5.00' }
        
        expect(flash[:notice]).to include("already been paid")
        expect(response).to redirect_to(tenant_invoice_path(invoice, access_token: invoice.guest_access_token))
      end
    end
    
    context "when tips are disabled" do
      before do
        business.update!(tips_enabled: false)
      end
      
      it "rejects tip when tips are disabled" do
        post :pay, params: { id: invoice.id, access_token: invoice.guest_access_token, tip_amount: '10.00' }
        
        expect(flash[:alert]).to include("Tips are not enabled")
        expect(response).to redirect_to(tenant_invoice_path(invoice, access_token: invoice.guest_access_token))
      end
    end
    
    context "when invoice has no tip-eligible items" do
      let!(:no_tip_product) { create(:product, business: business, tips_enabled: false) }
      let!(:no_tip_variant) { create(:product_variant, product: no_tip_product) }
      let!(:no_tip_order) { create(:order, business: business, tenant_customer: tenant_customer) }
      let!(:no_tip_line_item) { create(:line_item, lineable: no_tip_order, product_variant: no_tip_variant, quantity: 1) }
      let!(:no_tip_invoice) { create(:invoice, business: business, order: no_tip_order, tenant_customer: tenant_customer, status: :pending) }
      
      it "allows tip even when invoice has no tip-eligible items" do
        post :pay, params: { id: no_tip_invoice.id, access_token: no_tip_invoice.guest_access_token, tip_amount: '5.00' }
        
        # Payment processes successfully and tip is applied (controller doesn't validate this)
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(no_tip_invoice.reload.tip_amount).to eq(5.0)
      end
    end
  end
end 