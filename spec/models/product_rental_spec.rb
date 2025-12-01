# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Product Rental Features', type: :model do
  let(:business) { create(:business) }
  
  describe 'rental product creation' do
    it 'creates a rental product with valid attributes' do
      rental = build(:product, 
        business: business, 
        product_type: :rental,
        price: 50.00,
        hourly_rate: 10.00,
        weekly_rate: 200.00,
        security_deposit: 100.00,
        rental_quantity_available: 5,
        rental_category: 'equipment'
      )
      expect(rental).to be_valid
    end
    
    it 'requires daily rate (price) for rentals' do
      rental = build(:product, 
        business: business, 
        product_type: :rental,
        price: nil,
        rental_category: 'equipment'
      )
      expect(rental).not_to be_valid
    end
    
    it 'validates rental_category for rentals' do
      rental = build(:product, 
        business: business, 
        product_type: :rental,
        price: 50,
        rental_category: 'invalid_category'
      )
      expect(rental).not_to be_valid
    end
  end
  
  describe 'rental pricing calculation' do
    let(:rental) do
      create(:product, 
        business: business, 
        product_type: :rental,
        price: 50.00, # daily rate
        hourly_rate: 10.00,
        weekly_rate: 280.00,
        rental_quantity_available: 3
      )
    end
    
    it 'calculates hourly rental price' do
      start_time = Time.current
      end_time = start_time + 3.hours
      pricing = rental.calculate_rental_price(start_time, end_time, rate_type: 'hourly')
      
      expect(pricing[:rate_type]).to eq('hourly')
      expect(pricing[:rate]).to eq(10.00)
      expect(pricing[:quantity]).to eq(3)
      expect(pricing[:total]).to eq(30.00)
    end
    
    it 'calculates daily rental price' do
      start_time = Time.current
      end_time = start_time + 2.days
      pricing = rental.calculate_rental_price(start_time, end_time, rate_type: 'daily')
      
      expect(pricing[:rate_type]).to eq('daily')
      expect(pricing[:rate]).to eq(50.00)
      expect(pricing[:quantity]).to eq(2)
      expect(pricing[:total]).to eq(100.00)
    end
    
    it 'calculates weekly rental price' do
      start_time = Time.current
      end_time = start_time + 2.weeks
      pricing = rental.calculate_rental_price(start_time, end_time, rate_type: 'weekly')
      
      expect(pricing[:rate_type]).to eq('weekly')
      expect(pricing[:rate]).to eq(280.00)
      expect(pricing[:quantity]).to eq(2)
      expect(pricing[:total]).to eq(560.00)
    end
    
    it 'auto-selects optimal rate type' do
      # Short rental should be hourly
      short_pricing = rental.calculate_rental_price(Time.current, Time.current + 4.hours)
      expect(short_pricing[:rate_type]).to eq('hourly')
      
      # Medium rental should be daily
      medium_pricing = rental.calculate_rental_price(Time.current, Time.current + 3.days)
      expect(medium_pricing[:rate_type]).to eq('daily')
      
      # Long rental should be weekly
      long_pricing = rental.calculate_rental_price(Time.current, Time.current + 10.days)
      expect(long_pricing[:rate_type]).to eq('weekly')
    end
  end
  
  describe 'rental availability' do
    let(:rental) do
      create(:product, 
        business: business, 
        product_type: :rental,
        price: 50.00,
        rental_quantity_available: 2,
        rental_buffer_mins: 30
      )
    end
    let(:customer) { create(:tenant_customer, business: business) }
    
    before do
      # Create an existing booking
      create(:rental_booking,
        business: business,
        product: rental,
        tenant_customer: customer,
        start_time: 1.day.from_now,
        end_time: 3.days.from_now,
        quantity: 1,
        status: 'deposit_paid'
      )
    end
    
    it 'checks availability for a period' do
      # Should have 1 available (2 total - 1 booked)
      expect(rental.available_rental_quantity(1.day.from_now, 3.days.from_now)).to eq(1)
    end
    
    it 'returns true when rental is available' do
      expect(rental.rental_available_for?(1.day.from_now, 3.days.from_now, quantity: 1)).to be true
    end
    
    it 'returns false when requested quantity exceeds available' do
      expect(rental.rental_available_for?(1.day.from_now, 3.days.from_now, quantity: 2)).to be false
    end
    
    it 'considers buffer time' do
      # Try to book immediately after existing booking ends
      # Should account for 30 min buffer
      expect(rental.available_rental_quantity(3.days.from_now, 4.days.from_now)).to eq(1)
    end
  end
  
  describe 'rental duration constraints' do
    let(:rental) do
      create(:product, 
        business: business, 
        product_type: :rental,
        price: 50.00,
        min_rental_duration_mins: 60, # 1 hour minimum
        max_rental_duration_mins: 10080 # 1 week maximum
      )
    end
    
    it 'validates duration is within constraints' do
      # Valid: 2 days
      expect(rental.valid_rental_duration?(Time.current, Time.current + 2.days)).to be true
      
      # Too short: 30 minutes
      expect(rental.valid_rental_duration?(Time.current, Time.current + 30.minutes)).to be false
      
      # Too long: 2 weeks
      expect(rental.valid_rental_duration?(Time.current, Time.current + 2.weeks)).to be false
    end
    
    it 'displays duration constraints' do
      expect(rental.rental_duration_display).to include('Min:')
      expect(rental.rental_duration_display).to include('Max:')
    end
  end
  
  describe 'scopes' do
    before do
      @rental1 = create(:product, :rental, business: business, price: 50, rental_category: 'equipment')
      @rental2 = create(:product, :rental, business: business, price: 100, rental_category: 'vehicle')
      @standard = create(:product, business: business, product_type: :standard)
    end
    
    it 'filters to only rentals' do
      expect(Product.rentals).to include(@rental1, @rental2)
      expect(Product.rentals).not_to include(@standard)
    end
    
    it 'filters non-rentals' do
      expect(Product.non_rentals).to include(@standard)
      expect(Product.non_rentals).not_to include(@rental1, @rental2)
    end
    
    it 'filters by rental category' do
      expect(Product.by_rental_category('equipment')).to include(@rental1)
      expect(Product.by_rental_category('equipment')).not_to include(@rental2)
    end
  end
end

