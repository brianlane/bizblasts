# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalBooking, type: :model do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, :rental, business: business, price: 50, security_deposit: 100, rental_quantity_available: 3) }
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

  describe 'edge cases' do
    describe 'optimistic locking' do
      it 'prevents concurrent updates with stale data' do
        booking = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer)

        # Simulate two processes loading the same booking
        booking1 = RentalBooking.find(booking.id)
        booking2 = RentalBooking.find(booking.id)

        # First update succeeds
        booking1.update!(notes: "Update 1")

        # Second update should fail due to stale lock_version
        expect {
          booking2.update!(notes: "Update 2")
        }.to raise_error(ActiveRecord::StaleObjectError)
      end
    end

    describe 'Stripe minimum charge validation' do
      it 'rejects security deposits below $0.50' do
        low_deposit_product = create(:product, :rental, business: business, security_deposit: 0.25)
        booking = build(:rental_booking, business: business, product: low_deposit_product, tenant_customer: customer)

        expect(booking).not_to be_valid
        expect(booking.errors[:security_deposit_amount]).to include('must be at least $0.50 USD for Stripe processing')
      end

      it 'allows security deposits of exactly $0.50' do
        min_deposit_product = create(:product, :rental, business: business, security_deposit: 0.50)
        booking = build(:rental_booking, business: business, product: min_deposit_product, tenant_customer: customer)

        expect(booking).to be_valid
      end

      it 'allows zero security deposits' do
        no_deposit_product = create(:product, :rental, business: business, security_deposit: 0)
        booking = build(:rental_booking, business: business, product: no_deposit_product, tenant_customer: customer)

        expect(booking).to be_valid
      end
    end

    describe 'concurrent booking conflicts' do
      it 'prevents double-booking same rental item' do
        # First booking takes all available quantity
        booking1 = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          quantity: 3,
          start_time: 2.days.from_now,
          end_time: 4.days.from_now
        )

        # Second booking for overlapping period should fail validation
        booking2 = build(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          quantity: 1,
          start_time: 3.days.from_now,
          end_time: 5.days.from_now
        )

        expect(booking2).not_to be_valid
        expect(booking2.errors[:base]).to include('The requested rental is not available for the selected period and quantity')
      end

      it 'allows booking if quantity is available' do
        # First booking takes 2 of 3 available
        booking1 = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          quantity: 2,
          start_time: 2.days.from_now,
          end_time: 4.days.from_now
        )

        # Second booking for 1 should succeed
        booking2 = build(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          quantity: 1,
          start_time: 3.days.from_now,
          end_time: 5.days.from_now
        )

        expect(booking2).to be_valid
      end
    end

    describe 'timezone handling edge cases' do
      it 'handles DST transitions correctly' do
        # Create booking crossing DST boundary (if applicable to business timezone)
        business.update!(time_zone: 'America/New_York')

        booking = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          start_time: Time.zone.parse('2024-03-10 01:00:00'), # Day before DST
          end_time: Time.zone.parse('2024-03-10 04:00:00')    # Day of DST spring forward
        )

        expect(booking.local_start_time.zone).to eq('EST')
        expect(booking.duration_hours).to eq(2) # Lost hour due to DST
      end

      it 'uses business timezone for display times' do
        business.update!(time_zone: 'America/Los_Angeles')

        booking = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          start_time: Time.utc(2024, 1, 1, 18, 0, 0) # 6pm UTC
        )

        expect(booking.local_start_time.zone).to eq('PST')
        expect(booking.local_start_time.hour).to eq(10) # 10am PST
      end
    end

    describe 'late fee calculations' do
      let(:booking) do
        create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          start_time: 3.days.ago,
          end_time: 1.day.ago,
          status: 'checked_out'
        )
      end

      before do
        business.update!(
          rental_late_fee_enabled: true,
          rental_late_fee_percentage: 20.0
        )
      end

      it 'calculates late fees for overdue returns' do
        staff = create(:staff_member, business: business)

        # Return 2 days late
        Timecop.travel(1.day.from_now) do
          booking.process_return!(
            staff_member: staff,
            condition_rating: 'good',
            notes: 'Returned late'
          )
        end

        expect(booking.late_fee_amount).to be > 0
        expect(booking.deposit_status).to eq('partial_refund')
      end

      it 'does not charge late fees when returned on time' do
        staff = create(:staff_member, business: business)

        booking.process_return!(
          staff_member: staff,
          condition_rating: 'good'
        )

        expect(booking.late_fee_amount).to be_nil
      end
    end

    describe 'deposit refund calculations' do
      let(:staff) { create(:staff_member, business: business) }
      let(:booking) do
        create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          security_deposit_amount: 100,
          start_time: 2.days.ago,
          end_time: 1.day.ago,
          status: 'checked_out'
        )
      end

      it 'issues full refund when no damage or late fees' do
        booking.process_return!(
          staff_member: staff,
          condition_rating: 'excellent',
          damage_amount: 0
        )

        expect(booking.deposit_full_refund?).to be true
        expect(booking.deposit_refund_amount).to eq(100)
      end

      it 'issues partial refund when damage fee applied' do
        booking.process_return!(
          staff_member: staff,
          condition_rating: 'fair',
          damage_amount: 25
        )

        expect(booking.deposit_partial_refund?).to be true
        expect(booking.deposit_refund_amount).to eq(75)
        expect(booking.damage_fee_amount).to eq(25)
      end

      it 'forfeits deposit when fees exceed deposit amount' do
        booking.process_return!(
          staff_member: staff,
          condition_rating: 'damaged',
          damage_amount: 150
        )

        expect(booking.deposit_forfeited?).to be true
        expect(booking.deposit_refund_amount).to eq(0)
      end

      it 'combines late fees and damage fees' do
        business.update!(
          rental_late_fee_enabled: true,
          rental_late_fee_percentage: 50.0
        )

        Timecop.travel(2.days.from_now) do
          booking.process_return!(
            staff_member: staff,
            condition_rating: 'fair',
            damage_amount: 20
          )
        end

        total_fees = booking.late_fee_amount.to_d + booking.damage_fee_amount.to_d
        expect(booking.deposit_refund_amount).to eq(100 - total_fees)
      end
    end

    describe 'overdue status transitions' do
      it 'marks booking as overdue when end_time passes' do
        booking = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          start_time: 2.days.ago,
          end_time: 1.hour.ago,
          status: 'checked_out'
        )

        booking.mark_overdue!
        expect(booking.status_overdue?).to be true
      end

      it 'does not mark as overdue before end_time' do
        booking = create(:rental_booking,
          business: business,
          product: rental_product,
          tenant_customer: customer,
          start_time: 1.day.ago,
          end_time: 1.day.from_now,
          status: 'checked_out'
        )

        booking.mark_overdue!
        expect(booking.status_overdue?).to be false
      end
    end

    describe 'invalid state transitions' do
      let(:booking) { create(:rental_booking, business: business, product: rental_product, tenant_customer: customer) }

      it 'prevents checking out before deposit is paid' do
        staff = create(:staff_member, business: business)

        expect(booking.check_out!(staff_member: staff)).to be false
        expect(booking.status_pending_deposit?).to be true
      end

      it 'prevents returning before checking out' do
        staff = create(:staff_member, business: business)
        booking.mark_deposit_paid!

        expect(booking.process_return!(staff_member: staff, condition_rating: 'good')).to be false
      end

      it 'prevents completing before returning' do
        booking.update!(status: 'checked_out')

        expect(booking.complete!).to be false
      end

      it 'prevents canceling after checkout' do
        booking.update!(status: 'checked_out')

        expect(booking.cancel!).to be false
      end
    end

    describe 'booking number uniqueness' do
      it 'generates unique booking numbers within business scope' do
        booking1 = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer)
        booking2 = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer)

        expect(booking1.booking_number).to be_present
        expect(booking2.booking_number).to be_present
        expect(booking1.booking_number).not_to eq(booking2.booking_number)
      end

      it 'allows same booking number in different businesses' do
        other_business = create(:business)
        other_rental = create(:product, :rental, business: other_business)
        other_customer = create(:tenant_customer, business: other_business)

        # Force same booking number (unlikely but theoretically possible)
        booking1 = create(:rental_booking, business: business, product: rental_product, tenant_customer: customer)

        # Should not conflict across businesses
        expect {
          create(:rental_booking,
            business: other_business,
            product: other_rental,
            tenant_customer: other_customer,
            booking_number: booking1.booking_number
          )
        }.not_to raise_error
      end
    end
  end
end

