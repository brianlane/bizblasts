require 'rails_helper'

RSpec.describe Client::SubscriptionsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbusiness', hostname: 'testbusiness') }
  let(:client_user) { create(:user, :client) }
  let(:manager) { create(:user, :manager, business: business) }
  
  let(:tenant_customer) { create(:tenant_customer, business: business, email: client_user.email, name: client_user.full_name) }
  let(:product) { create(:product, business: business, subscription_enabled: true) }
  let(:service) { create(:service, business: business, subscription_enabled: true) }
  
  let!(:active_subscription) do
    create(:customer_subscription, :active, :product_subscription,
           business: business, tenant_customer: tenant_customer, product: product)
  end
  
  let!(:failed_subscription) do
    create(:customer_subscription, :failed, :service_subscription,
           business: business, tenant_customer: tenant_customer, service: service)
  end
  
  let!(:other_customer_subscription) do
    other_customer = create(:tenant_customer, business: business)
    create(:customer_subscription, :active, :product_subscription,
           business: business, tenant_customer: other_customer, product: product)
  end

  before do
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'Authorization' do
    context 'when not signed in' do
      it 'redirects to login' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when signed in as manager' do
      before { sign_in manager }

      it 'redirects with access denied' do
        get :index
        expect(response).to redirect_to(business_manager_dashboard_path)
        expect(flash[:alert]).to include('access this area')
      end
    end
  end

  describe 'Client Access' do
    before { sign_in client_user }

    describe 'GET #index' do
      it 'loads client subscriptions dashboard' do
        get :index
        
        expect(response).to be_successful
        expect(assigns(:customer_subscriptions)).to include(active_subscription, failed_subscription)
        expect(assigns(:customer_subscriptions)).not_to include(other_customer_subscription)
        expect(assigns(:businesses)).to include(business)
      end

      it 'includes proper associations' do
        get :index
        
        subscriptions = assigns(:customer_subscriptions)
        expect(subscriptions.first.association(:tenant_customer).loaded?).to be true
        expect(subscriptions.first.association(:product).loaded?).to be true
      end
    end

    describe 'GET #show' do
      it 'displays subscription details' do
        get :show, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
      end

      it 'prevents access to other customer subscriptions' do
        expect {
          get :show, params: { id: other_customer_subscription.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'GET #edit' do
      it 'loads subscription for editing' do
        get :edit, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
      end

      it 'prevents editing other customer subscriptions' do
        expect {
          get :edit, params: { id: other_customer_subscription.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'PATCH #update' do
      context 'with valid params' do
        let(:update_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              quantity: 3,
              customer_rebooking_preference: 'same_day_next_month',
              customer_out_of_stock_preference: 'substitute_product'
            }
          }
        end

        it 'updates subscription preferences' do
          patch :update, params: update_params
          
          active_subscription.reload
          expect(active_subscription.quantity).to eq(3)
          expect(active_subscription.customer_rebooking_preference).to eq('same_day_next_month')
          expect(response).to redirect_to(client_subscription_path(active_subscription))
          expect(flash[:notice]).to eq('Subscription updated successfully')
        end
      end

      context 'with invalid params' do
        let(:invalid_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              quantity: -1
            }
          }
        end

        it 'renders edit with errors' do
          patch :update, params: invalid_params
          
          expect(response).to render_template(:edit)
          expect(assigns(:customer_subscription).errors).to be_present
        end
      end

      it 'prevents updating other customer subscriptions' do
        expect {
          patch :update, params: { 
            id: other_customer_subscription.id,
            customer_subscription: { quantity: 5 }
          }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'POST #cancel' do
      context 'with confirmation' do
        it 'cancels subscription' do
          post :cancel, params: { id: active_subscription.id, confirmed: 'true' }
          
          active_subscription.reload
          expect(active_subscription.status).to eq('cancelled')
          expect(response).to redirect_to(client_subscriptions_path)
          expect(flash[:notice]).to eq('Subscription cancelled successfully')
        end
      end

      context 'without confirmation' do
        it 'shows confirmation page' do
          post :cancel, params: { id: active_subscription.id }
          
          expect(response).to be_successful
          expect(assigns(:customer_subscription)).to eq(active_subscription)
          expect(response).to render_template(:cancel)
        end
      end

      it 'prevents cancelling other customer subscriptions' do
        expect {
          post :cancel, params: { id: other_customer_subscription.id, confirmed: 'true' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'GET #billing_history' do
      let!(:transactions) do
        [
          create(:subscription_transaction, :completed, :billing,
                 customer_subscription: active_subscription, amount: 29.99),
          create(:subscription_transaction, :completed, :payment,
                 customer_subscription: active_subscription, amount: 29.99)
        ]
      end

      it 'displays billing history' do
        get :billing_history, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
        expect(assigns(:transactions)).to include(*transactions)
      end

      it 'prevents access to other customer billing history' do
        expect {
          get :billing_history, params: { id: other_customer_subscription.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'GET #preferences' do
      it 'loads customer preferences form' do
        get :preferences, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
      end
    end

    describe 'PATCH #update_preferences' do
      context 'with valid preferences' do
        let(:preference_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              customer_rebooking_preference: 'loyalty_points',
              customer_out_of_stock_preference: 'skip_month'
            }
          }
        end

        it 'updates customer preferences' do
          patch :update_preferences, params: preference_params
          
          active_subscription.reload
          expect(active_subscription.customer_rebooking_preference).to eq('loyalty_points')
          expect(active_subscription.customer_out_of_stock_preference).to eq('skip_month')
          expect(response).to redirect_to(client_subscription_path(active_subscription))
          expect(flash[:notice]).to eq('Preferences updated successfully')
        end
      end

      context 'with invalid preferences' do
        let(:invalid_preference_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              quantity: -1  # This should fail validation (quantity must be > 0)
            }
          }
        end

        it 'renders preferences with errors' do
          patch :update_preferences, params: invalid_preference_params
          
          expect(response).to render_template(:preferences)
          expect(assigns(:customer_subscription).errors).to be_present
        end
      end
    end
  end

  describe 'Multi-business isolation' do
    let(:other_business) { create(:business) }
    let(:other_client) { create(:user, :client) }
    let(:other_tenant_customer) { create(:tenant_customer, business: other_business, email: other_client.email, name: other_client.full_name) }
    let(:other_business_subscription) do
      ActsAsTenant.with_tenant(other_business) do
        create(:customer_subscription, business: other_business, tenant_customer: other_tenant_customer)
      end
    end

    before do
      @request.host = "#{other_business.hostname}.lvh.me"
      ActsAsTenant.current_tenant = other_business
      sign_in other_client
    end

    it 'prevents access to other business subscriptions' do
      get :index
      
      expect(response).to be_successful
      expect(assigns(:customer_subscriptions)).not_to include(active_subscription, failed_subscription)
    end

    it 'raises error when accessing other business subscription directly' do
      expect {
        get :show, params: { id: active_subscription.id }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'Edge cases' do
    before { sign_in client_user }

    context 'with no subscriptions' do
      before do
        active_subscription.destroy
        failed_subscription.destroy
      end

      it 'shows empty state' do
        get :index
        
        expect(response).to be_successful
        expect(assigns(:customer_subscriptions)).to be_empty
      end
    end

    context 'with cancelled subscription' do
      before { active_subscription.update!(status: 'cancelled') }

      it 'prevents further modification' do
        post :cancel, params: { id: active_subscription.id, confirmed: 'true' }
        
        expect(response).to redirect_to(client_subscription_path(active_subscription))
        expect(flash[:alert]).to eq('Cannot cancel this subscription at this time.')
      end
    end
  end
end 