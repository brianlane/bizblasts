require 'rails_helper'

RSpec.describe Payment, type: :model do
  # Custom association tests that understand the business logic
  describe 'associations' do
    it 'belongs to business (optional for orphaned payments)' do
      expect(Payment.reflect_on_association(:business)).to be_present
      expect(Payment.reflect_on_association(:business).options[:optional]).to be true
    end

    it 'belongs to invoice (optional for orphaned payments)' do
      expect(Payment.reflect_on_association(:invoice)).to be_present
      expect(Payment.reflect_on_association(:invoice).options[:optional]).to be true
    end

    it 'belongs to order (optional)' do
      expect(Payment.reflect_on_association(:order)).to be_present
      expect(Payment.reflect_on_association(:order).options[:optional]).to be true
    end

    it 'belongs to tenant_customer (optional for orphaned payments)' do
      expect(Payment.reflect_on_association(:tenant_customer)).to be_present
      expect(Payment.reflect_on_association(:tenant_customer).options[:optional]).to be true
    end
  end

  it { should validate_presence_of(:amount) }
  it { should validate_numericality_of(:amount).is_greater_than(0) }
  it { should validate_presence_of(:payment_method) }
  it { should validate_presence_of(:status) }

  it { should define_enum_for(:payment_method).with_values({ credit_card: 'credit_card', cash: 'cash', bank_transfer: 'bank_transfer', paypal: 'paypal', other: 'other' }).backed_by_column_of_type(:string) }
  it { should define_enum_for(:status).with_values({ pending: 0, completed: 1, failed: 2, refunded: 3 }) }
end 