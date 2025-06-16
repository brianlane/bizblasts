require 'rails_helper'

RSpec.describe "Subscription Cancellation Flow", type: :request do
  let(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let(:product) { create(:product, business: business, subscription_enabled: true) }
  let(:service) { create(:service, business: business, subscription_enabled: true) }
  let(:client_user) { create(:user, :client, email: 'client@example.com') }
  let(:business_user) { create(:user, :manager, email: 'manager@example.com') }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: client_user.email) }
  
  let!(:active_subscription) do
    create(:customer_subscription, :active, :product_subscription,
           business: business,
           product: product,
           tenant_customer: tenant_customer,
           subscription_price: 29.99,
           stripe_subscription_id: 'sub_test_123')
  end
  


  before do
    ActsAsTenant.current_tenant = business
    host! "#{business.subdomain}.example.com"
    
    # Mock Stripe cancellation service
    allow(SubscriptionStripeService).to receive(:new).and_return(
      double('stripe_service', cancel_stripe_subscription!: true)
    )
    
    # Mock email notifications
    allow(SubscriptionMailer).to receive(:subscription_cancelled).and_return(
      double('mailer', deliver_now: true)
    )

  end

  describe "client cancellation flow" do
    before { sign_in client_user }

    describe "GET /subscriptions/:id/cancel" do
      it "displays cancellation confirmation page" do
        get "/subscriptions/#{active_subscription.id}/cancel"
        
        expect(response).to be_successful
        expect(response.body).to include('Cancel Subscription')
        expect(response.body).to include(active_subscription.product.name)
        expect(response.body).to include('Are you sure you want to cancel')
      end

      it "prevents access to other customer subscriptions" do
        other_customer = create(:tenant_customer, business: business, email: 'other@example.com')
        other_subscription = create(:customer_subscription, :active, business: business, tenant_customer: other_customer)
        
        get "/subscriptions/#{other_subscription.id}/cancel"
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /subscriptions/:id/cancel" do
      context "with confirmation" do
        it "cancels active subscription successfully" do
          post "/subscriptions/#{active_subscription.id}/cancel", 
               params: { confirmed: 'true' }
          
          active_subscription.reload
          expect(active_subscription.status).to eq('cancelled')
          expect(active_subscription.cancelled_at).to be_present
          expect(response).to redirect_to('/subscriptions')
          expect(flash[:notice]).to eq('Subscription cancelled successfully')
        end

        it "sends cancellation notifications" do
          expect(SubscriptionMailer).to receive(:subscription_cancelled)
            .with(active_subscription).and_return(double('mailer', deliver_now: true))
          expect(BusinessMailer).to receive(:subscription_cancelled)
            .with(active_subscription).and_return(double('mailer', deliver_now: true))

          post "/subscriptions/#{active_subscription.id}/cancel", 
               params: { confirmed: 'true' }
        end

        it "cancels subscription in Stripe" do
          stripe_service = double('SubscriptionStripeService')
          expect(SubscriptionStripeService).to receive(:new).with(active_subscription).and_return(stripe_service)
          expect(stripe_service).to receive(:cancel_stripe_subscription!)

          post "/subscriptions/#{active_subscription.id}/cancel", 
               params: { confirmed: 'true' }
        end

        it "handles already cancelled subscriptions" do
          active_subscription.update!(status: :cancelled, cancelled_at: Time.current)
          
          post "/subscriptions/#{active_subscription.id}/cancel", 
               params: { confirmed: 'true' }
          
          expect(response).to redirect_to("/subscriptions/#{active_subscription.id}")
          expect(flash[:alert]).to eq('Cannot cancel this subscription at this time.')
        end
      end

      context "without confirmation" do
        it "renders confirmation page" do
          post "/subscriptions/#{active_subscription.id}/cancel"
          
          expect(response).to be_successful
          expect(response).to render_template(:cancel)
          expect(active_subscription.reload.status).to eq('active') # No change
        end
      end
    end


  end

  describe "business manager cancellation flow" do
    before do
      business.users << business_user
      sign_in business_user
      host! "#{business.subdomain}.example.com"
    end

    describe "PATCH /manage/subscriptions/:id/cancel" do
      it "cancels subscription with reason" do
        patch "/manage/subscriptions/#{active_subscription.id}/cancel",
              params: { cancellation_reason: 'Customer request via phone' }
        
        active_subscription.reload
        expect(active_subscription.status).to eq('cancelled')
        expect(active_subscription.cancellation_reason).to eq('Customer request via phone')
        expect(response).to redirect_to("/manage/subscriptions/#{active_subscription.id}")
        expect(flash[:notice]).to eq('Subscription has been cancelled.')
      end

      it "uses default reason when none provided" do
        patch "/manage/subscriptions/#{active_subscription.id}/cancel"
        
        active_subscription.reload
        expect(active_subscription.cancellation_reason).to eq('Cancelled by business manager')
      end

      it "prevents unauthorized access" do
        other_business = create(:business)
        other_customer = nil
        other_subscription = nil
        
        ActsAsTenant.with_tenant(other_business) do
          other_customer = create(:tenant_customer, business: other_business)
          other_subscription = create(:customer_subscription, business: other_business, tenant_customer: other_customer)
        end
        
        patch "/manage/subscriptions/#{other_subscription.id}/cancel"
        expect(response).to have_http_status(:not_found)
      end
    end



    describe "DELETE /manage/subscriptions/:id" do
      it "cancels subscription via DELETE action" do
        delete "/manage/subscriptions/#{active_subscription.id}"
        
        active_subscription.reload
        expect(active_subscription.status).to eq('cancelled')
        expect(active_subscription.cancellation_reason).to eq('Cancelled by business manager')
        expect(response).to redirect_to('/manage/subscriptions')
        expect(flash[:notice]).to eq('Subscription was successfully cancelled.')
      end
    end
  end

  describe "cancellation business logic" do
    it "prevents cancellation of already cancelled subscriptions" do
      cancelled_subscription = create(:customer_subscription, :cancelled,
                                     business: business,
                                     tenant_customer: tenant_customer)
      
      sign_in client_user
      
      post "/subscriptions/#{cancelled_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      
      expect(response).to redirect_to("/subscriptions/#{cancelled_subscription.id}")
      expect(flash[:alert]).to eq('Cannot cancel this subscription at this time.')
    end

    it "handles failed subscriptions differently" do
      failed_subscription = create(:customer_subscription, :failed,
                                  business: business,
                                  tenant_customer: tenant_customer)
      
      sign_in client_user
      
      post "/subscriptions/#{failed_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      
      failed_subscription.reload
      expect(failed_subscription.status).to eq('cancelled')
    end


  end

  describe "Stripe integration errors" do
    before { sign_in client_user }

    it "handles Stripe API errors gracefully" do
      allow_any_instance_of(SubscriptionStripeService).to receive(:cancel_stripe_subscription!)
        .and_raise(Stripe::StripeError, 'Subscription not found')
      
      post "/subscriptions/#{active_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      
      # Should still cancel locally even if Stripe fails
      active_subscription.reload
      expect(active_subscription.status).to eq('cancelled')
      expect(response).to redirect_to('/subscriptions')
    end

    it "logs Stripe cancellation errors" do
      # Remove the global mock for this test
      allow(SubscriptionStripeService).to receive(:new).and_call_original
      
      expect(Rails.logger).to receive(:error).with(/Failed to cancel Stripe subscription sub_test_123/)
      
      allow_any_instance_of(SubscriptionStripeService).to receive(:cancel_stripe_subscription!)
        .and_raise(Stripe::StripeError, 'API error')
      
      post "/subscriptions/#{active_subscription.id}/cancel", 
           params: { confirmed: 'true' }
    end
  end

  describe "notification failures" do
    before { sign_in client_user }

    it "continues cancellation even if email fails" do
      allow(SubscriptionMailer).to receive(:subscription_cancelled).and_raise(StandardError, 'Email service down')
      
      post "/subscriptions/#{active_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      
      active_subscription.reload
      expect(active_subscription.status).to eq('cancelled')
      expect(response).to redirect_to('/subscriptions')
    end
  end

  describe "multi-tenant isolation" do
    let(:other_business) { create(:business, subdomain: 'otherbiz', hostname: 'otherbiz') }
    let(:other_customer) { create(:tenant_customer, business: other_business) }
    let(:other_subscription) { create(:customer_subscription, business: other_business, tenant_customer: other_customer) }

    before { sign_in client_user }

    it "prevents cross-tenant subscription access" do
      post "/subscriptions/#{other_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      expect(response).to have_http_status(:not_found)
    end

    it "isolates cancellation data by tenant" do
      # Cancel subscription in current business
      post "/subscriptions/#{active_subscription.id}/cancel", 
           params: { confirmed: 'true' }
      
      # Verify other business data is unaffected
      ActsAsTenant.with_tenant(other_business) do
        expect(other_business.customer_subscriptions.cancelled.count).to eq(0)
      end
      
      # Verify current business has the cancellation
      expect(business.customer_subscriptions.cancelled.count).to eq(1)
    end
  end
end 