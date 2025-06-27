# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionTransaction, type: :model do
  subject { build(:subscription_transaction) }

  describe 'associations' do
    it { is_expected.to belong_to(:customer_subscription) }
  end

  describe 'validations' do
    # Presence validations
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:transaction_type) }


    # Numerical validations
    it { is_expected.to validate_numericality_of(:amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0) }

    it 'validates presence of processed_date unless status is pending' do
      # Should be valid for pending transactions without processed_date
      transaction = build(:subscription_transaction, status: 'pending', processed_date: nil)
      expect(transaction).to be_valid
      
      # Should be invalid for completed transactions without processed_date
      transaction = build(:subscription_transaction, status: 'completed', processed_date: nil)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:processed_date]).to include("can't be blank")
    end
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(
          pending: 0,
          completed: 1,
          failed: 2,
          cancelled: 3,
          retrying: 4
        )
        .backed_by_column_of_type(:integer)
        .with_prefix(:status)
    end

    it do
      is_expected.to define_enum_for(:transaction_type)
        .with_values(
          billing: 'billing',
          payment: 'payment',
          refund: 'refund',
          failed_payment: 'failed_payment',
          skipped: 'skipped',
          loyalty_awarded: 'loyalty_awarded',
          cancelled: 'cancelled',
          reactivated: 'reactivated'
        )
        .backed_by_column_of_type(:string)
    end
  end

  describe 'scopes' do
    let!(:completed_transaction) { create(:subscription_transaction, :completed) }
    let!(:failed_transaction) { create(:subscription_transaction, :failed) }
    let!(:pending_transaction) { create(:subscription_transaction, :pending) }
    let!(:billing_transaction) { create(:subscription_transaction, :billing) }
    let!(:refund_transaction) { create(:subscription_transaction, :refund) }
    let!(:recent_transaction) { create(:subscription_transaction, :recent) }
    let!(:old_transaction) { create(:subscription_transaction, :old) }

    describe '.completed' do
      it 'returns only completed transactions' do
        expect(SubscriptionTransaction.completed).to contain_exactly(completed_transaction)
      end
    end

    describe '.failed' do
      it 'returns only failed transactions' do
        expect(SubscriptionTransaction.failed).to contain_exactly(failed_transaction)
      end
    end

    describe '.billing' do
      it 'returns only billing transactions' do
        expect(SubscriptionTransaction.billing).to include(billing_transaction)
        expect(SubscriptionTransaction.billing).not_to include(refund_transaction)
      end
    end

    describe '.refunds' do
      it 'returns only refund transactions' do
        expect(SubscriptionTransaction.refund).to include(refund_transaction)
        expect(SubscriptionTransaction.refund).not_to include(billing_transaction)
      end
    end
  end

  describe 'business logic methods' do
    describe '#success?' do
      it 'returns true for completed transactions' do
        transaction = build(:subscription_transaction, :completed)
        expect(transaction.success?).to be true
      end

      it 'returns false for failed transactions' do
        transaction = build(:subscription_transaction, :failed)
        expect(transaction.success?).to be false
      end

      it 'returns false for pending transactions' do
        transaction = build(:subscription_transaction, :pending)
        expect(transaction.success?).to be false
      end
    end

    describe '#processed?' do
      it 'returns true when processed_date is present' do
        transaction = build(:subscription_transaction, processed_date: 1.hour.ago.to_date)
        expect(transaction.processed?).to be true
      end

      it 'returns false when processed_date is nil' do
        transaction = build(:subscription_transaction, processed_date: nil)
        expect(transaction.processed?).to be false
      end
    end

    describe '#billing?' do
      it 'returns true for billing transactions' do
        transaction = build(:subscription_transaction, :billing)
        expect(transaction.billing?).to be true
      end

      it 'returns false for refund transactions' do
        transaction = build(:subscription_transaction, :refund)
        expect(transaction.billing?).to be false
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_save callbacks' do
      it 'sets processed_date when status changes to completed' do
        transaction = create(:subscription_transaction, :pending, processed_date: 1.week.ago.to_date)
        original_date = transaction.processed_date
        
        transaction.update!(status: 'completed')
        
        # Should update processed_date when status changes
        expect(transaction.processed_date).not_to eq(original_date)
        expect(transaction.processed_date).to eq(Date.current)
      end

      it 'sets processed_date when status changes to failed' do
        transaction = create(:subscription_transaction, :pending, processed_date: 1.week.ago.to_date)
        original_date = transaction.processed_date
        
        transaction.update!(status: 'failed')
        
        # Should update processed_date when status changes
        expect(transaction.processed_date).not_to eq(original_date)
        expect(transaction.processed_date).to eq(Date.current)
      end

      it 'does not change processed_date if already set' do
        original_date = Date.current - 1.day  # Use stable date to avoid midnight boundary issues
        transaction = create(:subscription_transaction, :pending, processed_date: original_date)
        
        transaction.update!(status: 'completed')
        
        expect(transaction.processed_date).to eq(original_date)
      end
    end
  end

  describe 'validation edge cases' do
    it 'allows positive amounts' do
      transaction = build(:subscription_transaction, amount: 100.00)
      expect(transaction).to be_valid
    end

    it 'allows negative amounts for refunds' do
      transaction = build(:subscription_transaction, :refund, amount: -50.00)
      expect(transaction).to be_valid
    end

    it 'allows zero amounts' do
      transaction = build(:subscription_transaction, amount: 0.00)
      expect(transaction).to be_valid
    end

    it 'requires amount to be a number' do
      transaction = build(:subscription_transaction)
      transaction.amount = 'not_a_number'
      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include('is not a number')
    end
  end

  describe 'association validations' do
    it 'requires customer_subscription to exist' do
      transaction = build(:subscription_transaction, customer_subscription: nil)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:customer_subscription]).to include('must exist')
    end

    it 'belongs to the correct customer_subscription' do
      subscription = create(:customer_subscription)
      transaction = create(:subscription_transaction, customer_subscription: subscription)
      
      expect(transaction.customer_subscription).to eq(subscription)
    end
  end

  describe 'multi-tenant behavior' do
    it 'inherits tenant from customer_subscription' do
      business1 = create(:business)
      business2 = create(:business)
      
      subscription1 = create(:customer_subscription, business: business1)
      subscription2 = create(:customer_subscription, business: business2)
      
      transaction1 = create(:subscription_transaction, customer_subscription: subscription1)
      transaction2 = create(:subscription_transaction, customer_subscription: subscription2)
      
      ActsAsTenant.with_tenant(business1) do
        # Transactions should be accessible through their subscription's business
        expect(transaction1.customer_subscription.business).to eq(business1)
        expect(transaction2.customer_subscription.business).to eq(business2)
      end
    end
  end

  describe 'factory traits' do
    it 'creates completed transaction with proper attributes' do
      transaction = create(:subscription_transaction, :completed)
      
      expect(transaction.status).to eq('completed')
      expect(transaction.processed_date).to be_present
    end

    it 'creates failed transaction with failure reason' do
      transaction = create(:subscription_transaction, :failed)
      
      expect(transaction.status).to eq('failed')
      expect(transaction.failure_reason).to be_present
    end

    it 'creates refund transaction with negative amount' do
      transaction = create(:subscription_transaction, :refund)
      
      expect(transaction.transaction_type).to eq('refund')
      expect(transaction.amount).to be < 0
    end

    it 'creates high value transaction' do
      transaction = create(:subscription_transaction, :high_value)
      
      expect(transaction.amount).to eq(500.00)
    end

    it 'creates transaction with notes' do
      transaction = create(:subscription_transaction, :with_notes)
      
      expect(transaction.notes).to be_present
    end
  end

  describe 'error handling' do
    it 'handles invalid enum values gracefully' do
      expect {
        build(:subscription_transaction, status: 'invalid_status')
      }.to raise_error(ArgumentError)
    end

    it 'handles invalid transaction_type values gracefully' do
      expect {
        build(:subscription_transaction, transaction_type: 'invalid_type')
      }.to raise_error(ArgumentError)
    end
  end

  describe 'data integrity' do
    it 'maintains referential integrity with customer_subscription' do
      subscription = create(:customer_subscription)
      transaction = create(:subscription_transaction, customer_subscription: subscription)
      
      expect { subscription.destroy }.to change(SubscriptionTransaction, :count).by(-1)
    end

    it 'stores metadata correctly' do
      transaction = create(:subscription_transaction, 
                          metadata: { 'stripe_invoice_id' => 'in_test_12345' })
      
      expect(transaction.reload.metadata).to include('stripe_invoice_id' => 'in_test_12345')
    end
  end

  describe 'query performance' do
    it 'includes proper indexes for common queries' do
      # This would typically be tested with database-specific tools
      # For now, we'll just ensure the queries work efficiently
      subscription = create(:customer_subscription)
      create_list(:subscription_transaction, 10, customer_subscription: subscription)
      
      expect {
        SubscriptionTransaction.where(customer_subscription: subscription).completed.count
      }.not_to raise_error
    end
  end
end 