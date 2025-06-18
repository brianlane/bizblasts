require 'rails_helper'

RSpec.describe BusinessManager::CustomerSubscriptionsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbusiness', hostname: 'testbusiness') }
  let(:manager) { create(:user, :manager, business: business) }
  let(:staff) { create(:user, :staff, business: business) }
  let(:client) { create(:user, :client) }
  
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:product) { create(:product, business: business, subscription_enabled: true) }
  let(:service) { create(:service, business: business, subscription_enabled: true) }
  let(:product_variant) { create(:product_variant, product: product) }
  
  let!(:active_subscription) do
    create(:customer_subscription, :active, :product_subscription,
           business: business, tenant_customer: tenant_customer, product: product)
  end
  
  let!(:failed_subscription) do
    create(:customer_subscription, :failed, :service_subscription,
           business: business, tenant_customer: tenant_customer, service: service)
  end
  
  let!(:cancelled_subscription) do
    create(:customer_subscription, :cancelled, :product_subscription,
           business: business, tenant_customer: tenant_customer, product: product)
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

    context 'when signed in as client' do
      before { sign_in client }

      it 'redirects with access denied' do
        get :index
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to include('access this area')
      end
    end
  end

  describe 'Manager/Staff Access' do
    before { sign_in manager }

    describe 'GET #index' do
      it 'loads subscription dashboard successfully' do
        get :index
        
        expect(response).to be_successful
        expect(assigns(:customer_subscriptions)).to include(active_subscription, failed_subscription, cancelled_subscription)
        expect(assigns(:subscription_stats)).to be_present
        expect(assigns(:subscription_stats)[:total_active]).to eq(1)
        expect(assigns(:subscription_stats)[:product_subscriptions]).to eq(1)
        expect(assigns(:subscription_stats)[:service_subscriptions]).to eq(0)
      end

      context 'with status filter' do
        it 'filters subscriptions by status' do
          get :index, params: { status: 'active' }
          
          expect(assigns(:customer_subscriptions)).to include(active_subscription)
          expect(assigns(:customer_subscriptions)).not_to include(failed_subscription, cancelled_subscription)
        end
      end

      context 'with type filter' do
        it 'filters subscriptions by type' do
          get :index, params: { type: 'product_subscription' }
          
          expect(assigns(:customer_subscriptions)).to include(active_subscription, cancelled_subscription)
          expect(assigns(:customer_subscriptions)).not_to include(failed_subscription)
        end
      end

      context 'with search query' do
        it 'filters subscriptions by customer name' do
          get :index, params: { search: tenant_customer.full_name }
          
          expect(assigns(:customer_subscriptions)).to include(active_subscription, failed_subscription, cancelled_subscription)
        end
      end
    end

    describe 'GET #show' do
      it 'displays subscription details' do
        get :show, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
      end

      it 'prevents access to other business subscriptions' do
        other_business = create(:business)
        other_subscription = nil
        ActsAsTenant.with_tenant(other_business) do
          other_subscription = create(:customer_subscription, business: other_business)
        end
        
        expect {
          get :show, params: { id: other_subscription.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe 'GET #new' do
      it 'builds new subscription with collections' do
        get :new
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to be_a_new(CustomerSubscription)
        expect(assigns(:tenant_customers)).to include(tenant_customer)
        expect(assigns(:products)).to include(product)
        expect(assigns(:services)).to include(service)
      end
    end

    describe 'POST #create' do
      context 'with valid product subscription params' do
        let(:valid_params) do
          {
            customer_subscription: {
              tenant_customer_id: tenant_customer.id,
              subscription_type: 'product_subscription',
              product_id: product.id,
              product_variant_id: product_variant.id,
              quantity: 2,
              frequency: 'monthly',
              subscription_price: 29.99,
              billing_day_of_month: 15,
              next_billing_date: 1.month.from_now.to_date
            }
          }
        end

        it 'creates subscription and redirects' do
          expect {
            post :create, params: valid_params
          }.to change(business.customer_subscriptions, :count).by(1)

          subscription = business.customer_subscriptions.last
          expect(subscription.subscription_type).to eq('product_subscription')
          expect(subscription.product).to eq(product)
          expect(response).to redirect_to(business_manager_customer_subscription_path(subscription))
          expect(flash[:notice]).to eq('Subscription was successfully created.')
        end
      end

      context 'with valid service subscription params' do
        let(:valid_service_params) do
          {
            customer_subscription: {
              tenant_customer_id: tenant_customer.id,
              subscription_type: 'service_subscription',
              service_id: service.id,
              quantity: 1,
              frequency: 'weekly',
              subscription_price: 75.00,
              billing_day_of_month: 1,
              next_billing_date: 1.week.from_now.to_date
            }
          }
        end

        it 'creates service subscription' do
          expect {
            post :create, params: valid_service_params
          }.to change(business.customer_subscriptions, :count).by(1)

          subscription = business.customer_subscriptions.last
          expect(subscription.subscription_type).to eq('service_subscription')
          expect(subscription.service).to eq(service)
          expect(response).to redirect_to(business_manager_customer_subscription_path(subscription))
        end
      end

      context 'with invalid params' do
        let(:invalid_params) do
          {
            customer_subscription: {
              tenant_customer_id: nil,
              subscription_type: 'product_subscription',
              quantity: 0
            }
          }
        end

        it 'renders new with errors' do
          expect {
            post :create, params: invalid_params
          }.not_to change(business.customer_subscriptions, :count)

          expect(response).to render_template(:new)
          expect(assigns(:customer_subscription).errors).to be_present
        end
      end
    end

    describe 'GET #edit' do
      it 'loads subscription for editing' do
        get :edit, params: { id: active_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(active_subscription)
        expect(assigns(:tenant_customers)).to include(tenant_customer)
      end
    end

    describe 'PATCH #update' do
      context 'with valid params' do
        let(:update_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              quantity: 3,
              subscription_price: 39.99,
              customer_rebooking_preference: 'same_day_next_month'
            }
          }
        end

        it 'updates subscription and redirects' do
          patch :update, params: update_params
          
          active_subscription.reload
          expect(active_subscription.quantity).to eq(3)
          expect(active_subscription.subscription_price.to_f).to eq(39.99)
          expect(response).to redirect_to(business_manager_customer_subscription_path(active_subscription))
          expect(flash[:notice]).to eq('Subscription was successfully updated.')
        end
      end

      context 'with invalid params' do
        let(:invalid_update_params) do
          {
            id: active_subscription.id,
            customer_subscription: {
              quantity: -1,
              subscription_price: 0
            }
          }
        end

        it 'renders edit with errors' do
          patch :update, params: invalid_update_params
          
          expect(response).to render_template(:edit)
          expect(assigns(:customer_subscription).errors).to be_present
        end
      end
    end

    describe 'POST #cancel' do
      it 'cancels active subscription' do
        post :cancel, params: { id: active_subscription.id }
        
        active_subscription.reload
        expect(active_subscription.status).to eq('cancelled')
        expect(response).to redirect_to(business_manager_customer_subscription_path(active_subscription))
        expect(flash[:notice]).to eq('Subscription has been cancelled.')
      end

      it 'handles already cancelled subscription' do
        post :cancel, params: { id: cancelled_subscription.id }
        
        expect(response).to redirect_to(business_manager_customer_subscription_path(cancelled_subscription))
        expect(flash[:alert]).to eq('Unable to cancel subscription.')
      end
    end

    describe 'GET #analytics' do
      it 'loads subscription analytics' do
        get :analytics
        
        expect(response).to be_successful
        expect(assigns(:analytics_data)).to be_present
        expect(assigns(:analytics_data)[:monthly_revenue]).to be_present
        expect(assigns(:analytics_data)[:subscription_growth]).to be_present
      end
    end
  end

  describe 'Staff Access' do
    before { sign_in staff }

    it 'allows staff to access subscription management' do
      get :index
      expect(response).to be_successful
    end

    it 'allows staff to view subscription details' do
      get :show, params: { id: active_subscription.id }
      expect(response).to be_successful
    end
  end

  describe 'Multi-tenant isolation' do
    let(:other_business) { create(:business) }
    let(:other_manager) { create(:user, :manager, business: other_business) }
    
    before do
      @request.host = "#{other_business.hostname}.lvh.me"
      ActsAsTenant.current_tenant = other_business
      sign_in other_manager
    end

    it 'prevents access to other business subscriptions' do
      get :index
      
      expect(response).to be_successful
      expect(assigns(:customer_subscriptions)).not_to include(active_subscription, failed_subscription, cancelled_subscription)
    end

    it 'raises error when accessing other business subscription directly' do
      expect {
        get :show, params: { id: active_subscription.id }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end 