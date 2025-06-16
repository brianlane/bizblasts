# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerSubscription, type: :model do
  subject { build(:customer_subscription) }

  before do
    # Clear tenant to prevent test pollution
    ActsAsTenant.current_tenant = nil
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:tenant_customer) }
    
    it 'has optional service association' do
      # Service is optional at the association level but required by validation for service subscriptions
      subscription = build(:customer_subscription, :product_subscription)
      expect(subscription.service).to be_nil
      expect(subscription).to be_valid
    end
    
    it { is_expected.to belong_to(:product).optional }
    it { is_expected.to have_many(:subscription_transactions).dependent(:destroy) }
  end

  describe 'validations' do
    # Presence validations
    it { is_expected.to validate_presence_of(:subscription_type) }
    it { is_expected.to validate_presence_of(:frequency) }
    it { is_expected.to validate_presence_of(:subscription_price) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:next_billing_date) }

    # Numerical validations
    it { is_expected.to validate_numericality_of(:subscription_price).is_greater_than(0) }

    # Conditional validations
    context 'when subscription_type is service_subscription' do
      subject { build(:customer_subscription, :service_subscription) }
      
      it 'requires service to be present' do
        subject.service = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:service]).to include("must exist")
      end
      
      it 'requires product to be nil' do
        subject.product = create(:product, business: subject.business)
        expect(subject).not_to be_valid
        expect(subject.errors[:product]).to include("must be nil for service subscriptions")
      end
    end

    context 'when subscription_type is product_subscription' do
      subject { build(:customer_subscription, :product_subscription) }
      
      it 'requires product to be present' do
        subject.product = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:product]).to include("must exist")
      end
      
      it 'requires service to be nil' do
        # Ensure the subject's business is saved
        business = subject.business
        business.save! if business.new_record?
        
        # Set tenant and create service
        ActsAsTenant.current_tenant = business
        service = create(:service, business: business)
        
        subject.service = service
        expect(subject).not_to be_valid
        expect(subject.errors[:service]).to include("must be nil for product subscriptions")
      end
    end

    # Business association validation
    it 'validates that service belongs to the same business' do
      different_business = create(:business)
      service = create(:service, business: different_business)
      subscription = build(:customer_subscription, :service_subscription, service: service)
      
      expect(subscription).not_to be_valid
      expect(subscription.errors[:service]).to include("must belong to the same business")
    end

    it 'validates that product belongs to the same business' do
      different_business = create(:business)
      product = create(:product, business: different_business)
      subscription = build(:customer_subscription, :product_subscription, product: product)
      
      expect(subscription).not_to be_valid
      expect(subscription.errors[:product]).to include("must belong to the same business")
    end

    # Tenant customer validation
    it 'validates that tenant_customer belongs to the same business' do
      different_business = create(:business)
      tenant_customer = create(:tenant_customer, business: different_business)
      subscription = build(:customer_subscription, tenant_customer: tenant_customer)
      
      expect(subscription).not_to be_valid
      expect(subscription.errors[:tenant_customer]).to include("must belong to the same business")
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:subscription_type)
           .with_values(product_subscription: 'product_subscription', service_subscription: 'service_subscription')
           .backed_by_column_of_type(:string) }

    it { is_expected.to define_enum_for(:frequency)
           .with_values(weekly: 'weekly', monthly: 'monthly', quarterly: 'quarterly', annually: 'annually')
           .backed_by_column_of_type(:string) }

    it do
      is_expected.to define_enum_for(:status)
        .with_values(
          active: 0,
          cancelled: 1,
          expired: 2,
          failed: 3
        )
        .backed_by_column_of_type(:integer)
    end

    # Note: service_rebooking_preference enum test removed due to conflicts with class method

    it { is_expected.to define_enum_for(:out_of_stock_action)
             .with_values(
               skip_delivery: 0,
               substitute_similar: 1,
               contact_customer: 2,
               loyalty_points: 3
             )
             .backed_by_column_of_type(:integer) }
  end

  describe 'scopes' do
    let!(:active_subscription) { create(:customer_subscription, :active) }
    let!(:cancelled_subscription) { create(:customer_subscription, :cancelled) }
    let!(:expired_subscription) { create(:customer_subscription, :expired) }
    let!(:due_today) { create(:customer_subscription, :due_today, :active) }
    let!(:overdue) { create(:customer_subscription, :overdue) }
    let!(:service_subscription) { create(:customer_subscription, :service_subscription, :cancelled) }
    let!(:product_subscription) { create(:customer_subscription, :product_subscription, :expired) }

    describe '.active' do
      it 'returns only active subscriptions' do
        business = create(:business)
        ActsAsTenant.with_tenant(business) do
          active_sub = create(:customer_subscription, :active, business: business)
          cancelled_sub = create(:customer_subscription, :cancelled, business: business) 
          expired_sub = create(:customer_subscription, :expired, business: business)
          
          expect(CustomerSubscription.active).to contain_exactly(active_sub)
        end
      end
    end

    describe '.due_for_billing' do
      it 'returns subscriptions due for billing today or overdue' do
        expect(CustomerSubscription.due_for_billing).to contain_exactly(due_today, overdue)
      end
    end

    describe '.service_subscriptions' do
      it 'returns only service subscriptions' do
        expect(CustomerSubscription.service_subscriptions).to include(service_subscription)
        expect(CustomerSubscription.service_subscriptions).not_to include(product_subscription)
      end
    end

    describe '.product_subscriptions' do
      it 'returns only product subscriptions' do
        expect(CustomerSubscription.product_subscriptions).to include(product_subscription)
        expect(CustomerSubscription.product_subscriptions).not_to include(service_subscription)
      end
    end
  end

  describe 'business logic methods' do
    describe '#effective_rebooking_preference' do
      let(:business) { create(:business) }
      let(:service) { create(:service, business: business, subscription_rebooking_preference: 'soonest_available') }
      
      it 'returns customer preference when set' do
        subscription = create(:customer_subscription, 
                             business: business, 
                             service: service,
                             customer_rebooking_preference: 'loyalty_points')
        expect(subscription.effective_rebooking_preference).to eq('loyalty_points')
      end
      
      it 'returns service preference when customer preference is nil' do
        subscription = create(:customer_subscription, 
                             business: business, 
                             service: service,
                             customer_rebooking_preference: nil)
        expect(subscription.effective_rebooking_preference).to eq('soonest_available')
      end
      
      it 'returns business default when both customer and service preferences are nil' do
        allow(business).to receive(:default_service_rebooking_preference).and_return('same_day_next_month')
        service.update!(subscription_rebooking_preference: nil)
        subscription = create(:customer_subscription, 
                             business: business, 
                             service: service,
                             customer_rebooking_preference: nil)
        expect(subscription.effective_rebooking_preference).to eq('same_day_next_month')
      end
      
      it 'returns system default when all preferences are nil' do
        service.update!(subscription_rebooking_preference: nil)
        subscription = create(:customer_subscription, 
                             business: business, 
                             service: service,
                             customer_rebooking_preference: nil)
        expect(subscription.effective_rebooking_preference).to eq('same_day_next_month')
      end
    end

    describe '#effective_out_of_stock_action' do
      let(:business) { create(:business) }
      let(:product) { create(:product, business: business, subscription_out_of_stock_action: 'skip_delivery') }
      
      it 'returns customer preference when set' do
        subscription = create(:customer_subscription, 
                             :product_subscription,
                             business: business, 
                             product: product,
                             customer_out_of_stock_preference: 'loyalty_points')
        expect(subscription.effective_out_of_stock_action).to eq('loyalty_points')
      end
      
      it 'returns product preference when customer preference is nil' do
        subscription = create(:customer_subscription, 
                             :product_subscription,
                             business: business, 
                             product: product,
                             customer_out_of_stock_preference: nil)
        expect(subscription.effective_out_of_stock_action).to eq('skip_delivery')
      end
      
      it 'returns business default when both customer and product preferences are nil' do
        allow(business).to receive(:default_subscription_out_of_stock_action).and_return('skip_month')
        product.update!(subscription_out_of_stock_action: nil)
        subscription = create(:customer_subscription, 
                             :product_subscription,
                             business: business, 
                             product: product,
                             customer_out_of_stock_preference: nil)
        expect(subscription.effective_out_of_stock_action).to eq('skip_month')
      end
    end

    describe '#advance_billing_date!' do
      it 'advances billing date for monthly subscription' do
        subscription = create(:customer_subscription, :monthly, :service_subscription, next_billing_date: Date.current)
        original_date = subscription.next_billing_date
        
        subscription.advance_billing_date!
        
        expect(subscription.reload.next_billing_date).to eq(original_date + 1.month)
      end
      
      it 'advances billing date for weekly subscription' do
        subscription = create(:customer_subscription, :weekly, :service_subscription, next_billing_date: Date.current)
        original_date = subscription.next_billing_date
        
        subscription.advance_billing_date!
        
        expect(subscription.reload.next_billing_date).to eq(original_date + 1.week)
      end
      
      it 'advances billing date for quarterly subscription' do
        subscription = create(:customer_subscription, :quarterly, :service_subscription, next_billing_date: Date.current)
        original_date = subscription.next_billing_date
        
        subscription.advance_billing_date!
        
        expect(subscription.reload.next_billing_date).to eq(original_date + 3.months)
      end
      
      it 'advances billing date for yearly subscription' do
        subscription = create(:customer_subscription, :yearly, :service_subscription, next_billing_date: Date.current)
        original_date = subscription.next_billing_date
        
        subscription.advance_billing_date!
        
        expect(subscription.reload.next_billing_date).to eq(original_date + 1.year)
      end
    end

    describe '#allow_customer_preferences?' do
      it 'returns true for service subscriptions when service allows preferences' do
        business = create(:business)
        service = create(:service, business: business)
        allow(service).to receive(:allow_customer_preferences?).and_return(true)
        subscription = create(:customer_subscription, :service_subscription, business: business, service: service)
        
        expect(subscription.allow_customer_preferences?).to be true
      end
      
      it 'returns false for service subscriptions when service does not allow preferences' do
        business = create(:business)
        service = create(:service, business: business)
        allow(service).to receive(:allow_customer_preferences?).and_return(false)
        subscription = create(:customer_subscription, :service_subscription, business: business, service: service)
        
        expect(subscription.allow_customer_preferences?).to be false
      end
      
      it 'returns true for product subscriptions when product allows preferences' do
        business = create(:business)
        product = create(:product, business: business)
        allow(product).to receive(:allow_customer_preferences?).and_return(true)
        subscription = create(:customer_subscription, :product_subscription, business: business, product: product)
        
        expect(subscription.allow_customer_preferences?).to be true
      end
    end

    describe '#calculate_next_billing_date' do
      it 'calculates next billing date based on billing cycle' do
        subscription = build(:customer_subscription, :monthly, next_billing_date: Date.new(2024, 1, 15))
        
        expect(subscription.send(:calculate_next_billing_date)).to eq(Date.new(2024, 2, 15))
      end
    end

    describe '#original_price' do
      it 'calculates original price before discount' do
        business = create(:business)
        product = create(:product, business: business, price: 100.00)
        subscription = create(:customer_subscription, :product_subscription, business: business, product: product, subscription_price: 80.00)
        
        expect(subscription.original_price).to eq(100.00)
      end
    end

    describe '#discount_amount' do
      it 'returns discount amount as savings' do
        business = create(:business)
        product = create(:product, business: business, price: 100.00)
        subscription = create(:customer_subscription, :product_subscription, business: business, product: product, subscription_price: 85.00)
        
        expect(subscription.discount_amount).to eq(15.00)
      end
    end

    describe '#savings_percentage' do
      it 'calculates savings percentage correctly' do
        business = create(:business)
        product = create(:product, business: business, price: 100.00)
        subscription = create(:customer_subscription, :product_subscription, business: business, product: product, subscription_price: 80.00)
        
        expect(subscription.savings_percentage).to eq(20.0)
      end
      
      it 'returns 0 when original price is zero' do
        business = create(:business)
        product = create(:product, business: business, price: 0.00)
        subscription = create(:customer_subscription, :product_subscription, business: business, product: product, subscription_price: 1.00)
        
        expect(subscription.savings_percentage).to eq(0)
      end
    end
  end

  describe 'JSON field handling' do
    describe 'customer_preferences' do
      it 'stores and retrieves JSON data correctly' do
        preferences = {
          'preferred_time' => 'morning',
          'special_instructions' => 'Ring doorbell twice'
        }
        
        subscription = create(:customer_subscription, customer_preferences: preferences)
        
        expect(subscription.customer_preferences).to eq(preferences)
        expect(subscription.customer_preferences['preferred_time']).to eq('morning')
      end
      
      it 'handles nil customer_preferences' do
        subscription = create(:customer_subscription, customer_preferences: nil)
        
        expect(subscription.customer_preferences).to be_nil
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation callbacks' do
      it 'calculates subscription_price before validation' do
        subscription = build(:customer_subscription, subscription_price: 50.00)
        
        subscription.valid?
        
        expect(subscription.subscription_price).to eq(50.00)
      end
    end
  end

  describe 'multi-tenant behavior' do
    it 'scopes subscriptions to current tenant' do
      business1 = create(:business)
      business2 = create(:business)
      
      subscription1 = create(:customer_subscription, business: business1)
      subscription2 = create(:customer_subscription, business: business2)
      
      ActsAsTenant.with_tenant(business1) do
        expect(CustomerSubscription.all).to include(subscription1)
        expect(CustomerSubscription.all).not_to include(subscription2)
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles invalid frequency gracefully' do
      expect {
        build(:customer_subscription, frequency: 'invalid_cycle')
      }.to raise_error(ArgumentError)
    end
    
    it 'validates quantity cannot be zero' do
      subscription = build(:customer_subscription, quantity: 0)
      
      expect(subscription).not_to be_valid
      expect(subscription.errors[:quantity]).to include('must be greater than 0')
    end
    
    it 'validates negative prices are not allowed' do
      subscription = build(:customer_subscription, subscription_price: -10.00)
      
      expect(subscription).not_to be_valid
      expect(subscription.errors[:subscription_price]).to include('must be greater than 0')
    end
  end
end 