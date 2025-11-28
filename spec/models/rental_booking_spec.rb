# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalBooking, type: :model do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, business: business, product_type: :rental, price: 50, security_deposit: 100, rental_quantity_available: 3) }
  let(:customer) { create(:tenant_customer, business: business) }
  
  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:product) }
    it { should belong_to(:tenant_customer) }
    it { should belong_to(:product_variant).optional }
    it { should belong_to(:staff_member).optional }
    it { should belong_to(:location).optional }
    it { should belong_to(:promotion).optional }
    it { should have_many(:rental_condition_reports).dependent(:destroy) }
  end
  
  describe 'validations' do
    subject { build(:rental_booking, business: business, product: rental_product, tenant_customer: customer) }
    
    it { should validate_presence_of(:start_time) }
    it { should validate_presence_of(:end_time) }
    it { should validate_presence_of(:status) }
    
    it 'validates quantity is present and positive' do
      booking = build(:rental_booking, 
        business: business, 
        product: rental_product, 
        tenant_customer: customer,
        quantity: nil
      )
      expect(booking).not_to be_valid
    end
    
    it 'generates booking_number automatically' do
      booking = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer)
      expect(booking.booking_number).to be_present
      expect(booking.booking_number).to start_with('RNT-')
    end
    
    it 'validates end_time is after start_time' do
      booking = build(:rental_booking, 
        business: business, 
        product: rental_product, 
        tenant_customer: customer,
        start_time: 2.days.from_now,
        end_time: 1.day.from_now
      )
      expect(booking).not_to be_valid
      expect(booking.errors[:end_time]).to include('must be after start time')
    end
    
    it 'validates product is a rental' do
      standard_product = create(:product, business: business, product_type: :standard)
      booking = build(:rental_booking, 
        business: business, 
        product: standard_product, 
        tenant_customer: customer
      )
      expect(booking).not_to be_valid
      expect(booking.errors[:product]).to include('must be a rental product')
    end
  end
  
  describe 'status workflow' do
    let(:booking) { create(:rental_booking, business: business, product: rental_product, tenant_customer: customer) }
    
    describe '#mark_deposit_paid!' do
      it 'transitions from pending_deposit to deposit_paid' do
        expect(booking.status_pending_deposit?).to be true
        booking.mark_deposit_paid!(payment_intent_id: 'pi_test123')
        expect(booking.status_deposit_paid?).to be true
        expect(booking.deposit_collected?).to be true
        expect(booking.deposit_paid_at).to be_present
      end
      
      it 'does not transition from other states' do
        booking.update!(status: 'checked_out')
        expect(booking.mark_deposit_paid!).to be false
      end
    end
    
    describe '#can_check_out?' do
      it 'returns true when deposit is paid and start time has passed' do
        booking.update!(status: 'deposit_paid', start_time: 1.hour.ago)
        expect(booking.can_check_out?).to be true
      end
      
      it 'returns false when deposit is not paid' do
        expect(booking.can_check_out?).to be false
      end
    end
    
    describe '#can_cancel?' do
      it 'returns true when pending_deposit' do
        expect(booking.can_cancel?).to be true
      end
      
      it 'returns true when deposit_paid' do
        booking.update!(status: 'deposit_paid')
        expect(booking.can_cancel?).to be true
      end
      
      it 'returns false when checked_out' do
        booking.update!(status: 'checked_out')
        expect(booking.can_cancel?).to be false
      end
    end
  end
  
  describe 'duration helpers' do
    let(:booking) do
      create(:rental_booking, 
        business: business, 
        product: rental_product, 
        tenant_customer: customer,
        start_time: Time.zone.parse('2024-01-01 10:00:00'),
        end_time: Time.zone.parse('2024-01-03 10:00:00')
      )
    end
    
    it 'calculates duration_hours correctly' do
      # Exactly 48 hours
      expect(booking.duration_hours).to eq(48)
    end
    
    it 'calculates duration_days correctly' do
      # 48 hours = 2 days
      expect(booking.duration_days).to eq(2)
    end
    
    it 'calculates duration_minutes correctly' do
      expect(booking.duration_minutes).to eq(2880) # 48 * 60
    end
  end
  
  describe 'scopes' do
    before do
      @pending = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer, status: 'pending_deposit')
      @deposit_paid = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer, status: 'deposit_paid')
      @checked_out = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer, status: 'checked_out')
    end
    
    it 'filters by status' do
      expect(RentalBooking.status_pending_deposit).to include(@pending)
      expect(RentalBooking.status_deposit_paid).to include(@deposit_paid)
      expect(RentalBooking.status_checked_out).to include(@checked_out)
    end
    
    it 'returns active rentals' do
      expect(RentalBooking.active).to include(@deposit_paid, @checked_out)
      expect(RentalBooking.active).not_to include(@pending)
    end
  end
end

