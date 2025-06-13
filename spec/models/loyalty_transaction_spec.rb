require 'rails_helper'

RSpec.describe LoyaltyTransaction, type: :model do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe 'associations' do
    it { should belong_to(:tenant_customer) }
    it { should belong_to(:related_booking).optional }
    it { should belong_to(:related_order).optional }
    it { should belong_to(:related_referral).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:transaction_type) }
    it { should validate_inclusion_of(:transaction_type).in_array(%w[earned redeemed expired adjusted]) }
    it { should validate_presence_of(:points_amount) }
    it { should validate_presence_of(:description) }
    
    it 'validates points_amount is not zero' do
      transaction = build(:loyalty_transaction, points_amount: 0)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:points_amount]).to include('must be other than 0')
    end
  end

  describe 'scopes' do
    let!(:earned_transaction) { create(:loyalty_transaction, transaction_type: 'earned', tenant_customer: tenant_customer) }
    let!(:redeemed_transaction) { create(:loyalty_transaction, transaction_type: 'redeemed', tenant_customer: tenant_customer) }
    let!(:expired_transaction) { create(:loyalty_transaction, transaction_type: 'expired', tenant_customer: tenant_customer) }
    let!(:adjusted_transaction) { create(:loyalty_transaction, transaction_type: 'adjusted', tenant_customer: tenant_customer) }

    it 'filters by transaction type' do
      expect(LoyaltyTransaction.earned).to include(earned_transaction)
      expect(LoyaltyTransaction.earned).not_to include(redeemed_transaction)
      
      expect(LoyaltyTransaction.redeemed).to include(redeemed_transaction)
      expect(LoyaltyTransaction.redeemed).not_to include(earned_transaction)
      
      expect(LoyaltyTransaction.expired).to include(expired_transaction)
      expect(LoyaltyTransaction.adjusted).to include(adjusted_transaction)
    end

    it 'orders by recent first' do
      older_transaction = create(:loyalty_transaction, tenant_customer: tenant_customer)
      sleep(0.01) # Small delay to ensure different timestamps
      newer_transaction = create(:loyalty_transaction, tenant_customer: tenant_customer)
      
      expect(LoyaltyTransaction.recent.first).to eq(newer_transaction)
      expect(LoyaltyTransaction.recent.to_a).to include(older_transaction)
    end

    it 'filters by customer' do
      other_customer = create(:tenant_customer, business: business)
      other_transaction = create(:loyalty_transaction, tenant_customer: other_customer)
      
      customer_transactions = LoyaltyTransaction.for_customer(tenant_customer)
      expect(customer_transactions).to include(earned_transaction)
      expect(customer_transactions).not_to include(other_transaction)
    end
  end

  describe 'instance methods' do
    describe 'transaction type predicates' do
      it 'correctly identifies earned transactions' do
        transaction = create(:loyalty_transaction, transaction_type: 'earned', tenant_customer: tenant_customer)
        expect(transaction.earned?).to be true
        expect(transaction.redeemed?).to be false
        expect(transaction.expired?).to be false
        expect(transaction.adjusted?).to be false
      end

      it 'correctly identifies redeemed transactions' do
        transaction = create(:loyalty_transaction, transaction_type: 'redeemed', tenant_customer: tenant_customer)
        expect(transaction.redeemed?).to be true
        expect(transaction.earned?).to be false
      end
    end

    describe 'points amount predicates' do
      it 'correctly identifies positive points' do
        transaction = create(:loyalty_transaction, points_amount: 100, tenant_customer: tenant_customer)
        expect(transaction.positive_points?).to be true
        expect(transaction.negative_points?).to be false
      end

      it 'correctly identifies negative points' do
        transaction = create(:loyalty_transaction, points_amount: -50, tenant_customer: tenant_customer)
        expect(transaction.negative_points?).to be true
        expect(transaction.positive_points?).to be false
      end
    end
  end

  describe 'class methods' do
    let!(:customer1) { create(:tenant_customer, business: business) }
    let!(:customer2) { create(:tenant_customer, business: business) }
    
    before do
      create(:loyalty_transaction, transaction_type: 'earned', points_amount: 100, tenant_customer: customer1)
      create(:loyalty_transaction, transaction_type: 'earned', points_amount: 50, tenant_customer: customer1)
      create(:loyalty_transaction, transaction_type: 'redeemed', points_amount: -30, tenant_customer: customer1)
      create(:loyalty_transaction, transaction_type: 'earned', points_amount: 75, tenant_customer: customer2)
    end

    describe '.total_earned_for_customer' do
      it 'calculates total earned points for a customer' do
        expect(LoyaltyTransaction.total_earned_for_customer(customer1)).to eq(150)
        expect(LoyaltyTransaction.total_earned_for_customer(customer2)).to eq(75)
      end
    end

    describe '.total_redeemed_for_customer' do
      it 'calculates total redeemed points for a customer' do
        expect(LoyaltyTransaction.total_redeemed_for_customer(customer1)).to eq(30)
        expect(LoyaltyTransaction.total_redeemed_for_customer(customer2)).to eq(0)
      end
    end

    describe '.current_balance_for_customer' do
      it 'calculates current point balance for a customer' do
        expect(LoyaltyTransaction.current_balance_for_customer(customer1)).to eq(120) # 150 - 30
        expect(LoyaltyTransaction.current_balance_for_customer(customer2)).to eq(75)
      end
    end
  end

  describe 'tenant scoping' do
    let(:other_business) { create(:business) }
    let(:other_customer) { create(:tenant_customer, business: other_business) }
    
    it 'only shows transactions for current tenant' do
      transaction1 = create(:loyalty_transaction, tenant_customer: tenant_customer)
      
      ActsAsTenant.current_tenant = other_business
      transaction2 = create(:loyalty_transaction, tenant_customer: other_customer)
      
      ActsAsTenant.current_tenant = business
      expect(LoyaltyTransaction.all).to include(transaction1)
      expect(LoyaltyTransaction.all).not_to include(transaction2)
    end
  end

  describe 'related record associations' do
    let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer) }
    let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
    let(:referral) { create(:referral, business: business) }

    it 'can be associated with a booking' do
      transaction = create(:loyalty_transaction, 
                          tenant_customer: tenant_customer,
                          related_booking: booking)
      
      expect(transaction.related_booking).to eq(booking)
      expect(transaction.related_order).to be_nil
      expect(transaction.related_referral).to be_nil
    end

    it 'can be associated with an order' do
      transaction = create(:loyalty_transaction, 
                          tenant_customer: tenant_customer,
                          related_order: order)
      
      expect(transaction.related_order).to eq(order)
      expect(transaction.related_booking).to be_nil
      expect(transaction.related_referral).to be_nil
    end

    it 'can be associated with a referral' do
      transaction = create(:loyalty_transaction, 
                          tenant_customer: tenant_customer,
                          related_referral: referral)
      
      expect(transaction.related_referral).to eq(referral)
      expect(transaction.related_booking).to be_nil
      expect(transaction.related_order).to be_nil
    end
  end
end 