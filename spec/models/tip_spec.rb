require 'rails_helper'

RSpec.describe Tip, type: :model do
  let(:business) { create(:business, tips_enabled: true) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:experience_service) { create(:service, business: business, service_type: :experience, duration: 60, min_bookings: 1, max_bookings: 10, spots: 5) }
  let(:booking) { create(:booking, business: business, service: experience_service, tenant_customer: tenant_customer, start_time: 2.hours.ago) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe 'associations' do
    it 'belongs to business' do
      # Test that business association exists
      tip = create(:tip, business: business, booking: booking, tenant_customer: tenant_customer)
      expect(tip.business).to eq(business)
    end
    
    it { should belong_to(:booking).required }
    it { should belong_to(:tenant_customer).required }
  end

  describe 'validations' do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    
    it 'validates uniqueness of booking_id scoped to business_id' do
      create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, amount: 5.00)
      duplicate_tip = build(:tip, business: business, booking: booking, tenant_customer: tenant_customer, amount: 10.00)
      
      expect(duplicate_tip).not_to be_valid
      expect(duplicate_tip.errors[:booking_id]).to include('has already been taken')
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: 0, completed: 1, failed: 2) }
  end

  describe 'scopes' do
    let!(:pending_tip) { create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, status: :pending) }
    let!(:completed_tip) { create(:tip, business: business, booking: create(:booking, business: business, service: experience_service, tenant_customer: tenant_customer), tenant_customer: tenant_customer, status: :completed) }
    let!(:failed_tip) { create(:tip, business: business, booking: create(:booking, business: business, service: experience_service, tenant_customer: tenant_customer), tenant_customer: tenant_customer, status: :failed) }

    describe '.successful' do
      it 'returns only completed tips' do
        expect(Tip.successful).to contain_exactly(completed_tip)
      end
    end

    describe '.pending' do
      it 'returns only pending tips' do
        expect(Tip.pending).to contain_exactly(pending_tip)
      end
    end
  end

  describe '#mark_as_completed!' do
    let(:tip) { create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, status: :pending) }

    it 'updates status to completed and sets paid_at' do
          current_time = Time.current
    allow(Time).to receive(:current).and_return(current_time)
    
    tip.mark_as_completed!
    
    expect(tip.reload.status).to eq('completed')
    expect(tip.paid_at).to eq(current_time)
    end
  end

  describe '#mark_as_failed!' do
    let(:tip) { create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, status: :pending) }

    it 'updates status to failed' do
      tip.mark_as_failed!
      
      expect(tip.reload.status).to eq('failed')
    end

    it 'sets failure reason when provided' do
      reason = 'Card declined'
      tip.mark_as_failed!(reason)
      
      expect(tip.reload.failure_reason).to eq(reason)
    end
  end

  describe '#eligible_for_payment?' do
    context 'when booking is for an experience service' do
      let(:tip) { create(:tip, business: business, booking: booking, tenant_customer: tenant_customer) }

      context 'when experience is completed' do
        before do
          # Set booking start time to 2 hours ago with 60 minute duration
          booking.update!(start_time: 2.hours.ago)
        end

        it 'returns true' do
          expect(tip.eligible_for_payment?).to be true
        end
      end

      context 'when experience is not yet completed' do
        before do
          # Set booking start time to future
          booking.update!(start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        end

        it 'returns false' do
          expect(tip.eligible_for_payment?).to be false
        end
      end
    end

    context 'when booking is for a standard service' do
      let(:standard_service) { create(:service, business: business, service_type: :standard) }
      let(:standard_booking) { create(:booking, business: business, service: standard_service, tenant_customer: tenant_customer) }
      let(:tip) { create(:tip, business: business, booking: standard_booking, tenant_customer: tenant_customer) }

      it 'returns false' do
        expect(tip.eligible_for_payment?).to be false
      end
    end

    context 'when booking is nil' do
      let(:tip) { build(:tip, business: business, booking: nil, tenant_customer: tenant_customer) }

      it 'returns false' do
        expect(tip.eligible_for_payment?).to be false
      end
    end
  end

  describe 'ransackable attributes' do
    it 'includes expected attributes' do
      expected_attributes = %w[id amount status paid_at created_at updated_at business_id booking_id tenant_customer_id stripe_fee_amount platform_fee_amount business_amount]
      expect(Tip.ransackable_attributes).to match_array(expected_attributes)
    end
  end

  describe 'ransackable associations' do
    it 'includes expected associations' do
      expected_associations = %w[business booking tenant_customer]
      expect(Tip.ransackable_associations).to match_array(expected_associations)
    end
  end
end 