require 'rails_helper'

RSpec.describe Public::SubscriptionsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbusiness', hostname: 'testbusiness') }
  let(:client_user) { create(:user, :client) }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: client_user.email, first_name: client_user.first_name, last_name: client_user.last_name) }
  
  let(:product) { create(:product, business: business, subscription_enabled: true, price: 29.99) }
  let(:service) { create(:service, business: business, subscription_enabled: true, price: 75.00) }
  
  # Mock subscription pricing methods
  before do
    allow(product).to receive(:subscription_price).and_return(26.99) if defined?(product)
    allow(service).to receive(:subscription_price).and_return(67.50) if defined?(service)
  end

  before do
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    
    # Enable subscriptions for business
    allow(business).to receive(:subscription_discount_enabled?).and_return(true)
    allow(business).to receive(:subscription_discount_percentage).and_return(10) # 10% discount
    
    # Mock Stripe service calls
    allow(StripeService).to receive(:create_subscription_checkout_session).and_return({
      success: true,
      session: double('Stripe::Checkout::Session', id: 'cs_test_123', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET #new' do
    context 'with product subscription' do
      it 'displays product subscription signup page' do
        get :new, params: { product_id: product.id }
        
        expect(response).to be_successful
        expect(assigns(:product)).to eq(product)
        expect(assigns(:customer_subscription)).to be_a_new(CustomerSubscription)
        expect(assigns(:original_price)).to eq(product.price.to_f)
      end

      it 'redirects for non-subscription enabled product' do
        product.update!(subscription_enabled: false)
        
        get :new, params: { product_id: product.id }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Subscriptions not available for this product.')
      end

      it 'raises error for other business product' do
        other_business = create(:business)
        other_product = nil
        ActsAsTenant.with_tenant(other_business) do
          other_product = create(:product, business: other_business)
        end
        
        expect {
          get :new, params: { product_id: other_product.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with service subscription' do
      it 'displays service subscription signup page' do
        get :new, params: { service_id: service.id }
        
        expect(response).to be_successful
        expect(assigns(:service)).to eq(service)
        expect(assigns(:customer_subscription)).to be_a_new(CustomerSubscription)
        expect(assigns(:original_price)).to eq(service.price.to_f)
      end

      it 'redirects for non-subscription enabled service' do
        service.update!(subscription_enabled: false)
        
        get :new, params: { service_id: service.id }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Subscriptions not available for this service.')
      end
    end

    context 'with no product or service' do
      it 'redirects with error' do
        get :new
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Invalid subscription request.')
      end
    end

    context 'when subscriptions disabled' do
      before do 
        allow(business).to receive(:subscription_discount_enabled?).and_return(false)
        allow_any_instance_of(Public::SubscriptionsController).to receive(:current_business).and_return(business)
      end

      it 'redirects with error' do
        get :new, params: { product_id: product.id }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Subscriptions are not available.')
      end
    end
  end

  describe 'POST #create' do
    context 'with product subscription for guest customer' do
      let(:guest_params) do
        {
          product_id: product.id,
          customer_subscription: {
            subscription_type: 'product_subscription',
            quantity: 2,
            frequency: 'monthly',
            tenant_customer_attributes: {
              first_name: 'John', last_name: 'Doe',
              email: 'john@example.com',
              phone: '555-1234'
            }
          }
        }
      end

      it 'creates tenant customer and redirects to Stripe checkout' do
        expect {
          post :create, params: guest_params
        }.to change(business.tenant_customers, :count).by(1)

        created_customer = business.tenant_customers.last
        expect(created_customer.full_name).to eq('John Doe')
        expect(created_customer.email).to eq('john@example.com')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
      end
    end

    context 'with service subscription for existing customer' do
      before do 
        sign_in client_user
        # Ensure tenant_customer exists for the signed-in user
        tenant_customer # This triggers the let! block
      end

      let(:existing_customer_params) do
        {
          service_id: service.id,
          customer_subscription: {
            subscription_type: 'service_subscription',
            quantity: 1,
            frequency: 'weekly'
          }
        }
      end

      it 'uses existing customer and redirects to Stripe checkout' do
        expect {
          post :create, params: existing_customer_params
        }.not_to change(business.tenant_customers, :count)

        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
      end
    end

    context 'with invalid tenant customer params' do
              let(:invalid_params) do
          {
            product_id: product.id,
            customer_subscription: {
              subscription_type: 'product_subscription',
              quantity: 1,
              frequency: 'monthly',
              tenant_customer_attributes: {
                first_name: '',
                last_name: '',
                email: 'invalid-email'
              }
            }
          }
        end

      it 'renders form with errors' do
        post :create, params: invalid_params

        expect(response).to render_template(:new)
        expect(response.status).to eq(422)
      end
    end

          context 'with Stripe service error' do
        before do
          allow(StripeService).to receive(:create_subscription_checkout_session).and_return({
            success: false,
            error: 'Payment processing unavailable'
          })
        end

        let(:valid_params) do
          {
            product_id: product.id,
            customer_subscription: {
              subscription_type: 'product_subscription',
              quantity: 1,
              frequency: 'monthly',
              tenant_customer_attributes: {
                first_name: 'Jane', last_name: 'Doe',
                email: 'jane@example.com',
                phone: '555-5678'
              }
            }
          }
        end

      it 'handles Stripe errors gracefully' do
        post :create, params: valid_params
        
        expect(response).to render_template(:new)
        expect(flash[:alert]).to eq('Payment processing unavailable')
      end
    end

          context 'with development mode Stripe error' do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
          allow(StripeService).to receive(:create_subscription_checkout_session).and_return({
            success: false,
            error: 'Stripe not configured'
          })
        end

        let(:valid_params) do
          {
            product_id: product.id,
            customer_subscription: {
              subscription_type: 'product_subscription',
              quantity: 1,
              frequency: 'monthly',
              tenant_customer_attributes: {
                first_name: 'Jane', last_name: 'Doe',
                email: 'jane@example.com',
                phone: '555-5678'
              }
            }
          }
        end

      it 'shows development-friendly message' do
        post :create, params: valid_params
        
        expect(response).to render_template(:new)
        expect(flash[:notice]).to include('Subscription form is working!')
      end
    end

          context 'with exception during processing' do
        before do
          allow(StripeService).to receive(:create_subscription_checkout_session).and_raise(StandardError.new('Unexpected error'))
        end

        let(:valid_params) do
          {
            product_id: product.id,
            customer_subscription: {
              subscription_type: 'product_subscription',
              quantity: 1,
              frequency: 'monthly',
              tenant_customer_attributes: {
                first_name: 'Jane', last_name: 'Doe',
                email: 'jane@example.com',
                phone: '555-5678'
              }
            }
          }
        end

      it 'handles exceptions gracefully' do
        post :create, params: valid_params
        
        expect(response).to render_template(:new)
        expect(flash[:alert]).to eq('Unable to process subscription. Please try again.')
      end
    end
  end

  describe 'GET #confirmation' do
    let!(:customer_subscription) do
      create(:customer_subscription, :product_subscription,
             business: business, 
             tenant_customer: tenant_customer,
             product: product)
    end

    context 'with signed in user' do
      before { sign_in client_user }

      it 'displays confirmation for own subscription' do
        get :confirmation, params: { id: customer_subscription.id }
        
        expect(response).to be_successful
        expect(assigns(:customer_subscription)).to eq(customer_subscription)
      end

      it 'denies access to other user subscription' do
        other_customer = create(:tenant_customer, business: business, email: 'other@example.com')
        other_subscription = create(:customer_subscription, :product_subscription, business: business, tenant_customer: other_customer, product: product)
        
                  get :confirmation, params: { id: other_subscription.id }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Access denied.')
      end
    end

    context 'without parameters' do
      it 'redirects with error' do
        get :confirmation, params: { id: 99999 } # Non-existent ID
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Subscription not found.')
      end
    end
  end

  describe 'Multi-business isolation' do
    let(:other_business) { create(:business) }
    let(:other_product) do
      ActsAsTenant.with_tenant(other_business) do
        create(:product, business: other_business, subscription_enabled: true)
      end
    end

    before do
      @request.host = "#{business.hostname}.lvh.me"
      ActsAsTenant.current_tenant = business
    end

    it 'prevents access to other business products' do
      expect {
        get :new, params: { product_id: other_product.id }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end 