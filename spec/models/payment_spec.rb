require 'rails_helper'

RSpec.describe Payment, type: :model do
  it { should belong_to(:business) }
  it { should belong_to(:invoice) }
  it { should belong_to(:order).optional }
  it { should belong_to(:tenant_customer) }

  it { should validate_presence_of(:amount) }
  it { should validate_numericality_of(:amount).is_greater_than(0) }
  it { should validate_presence_of(:payment_method) }
  it { should validate_presence_of(:status) }

  it { should define_enum_for(:payment_method).with_values({ credit_card: 'credit_card', cash: 'cash', bank_transfer: 'bank_transfer', paypal: 'paypal', other: 'other' }).backed_by_column_of_type(:string) }
  it { should define_enum_for(:status).with_values({ pending: 0, completed: 1, failed: 2, refunded: 3 }) }
end 