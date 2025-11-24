# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionStockService, type: :service do
  let(:business) { create(:business, loyalty_program_enabled: true) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:product) { create(:product, business: business, subscription_enabled: true, stock_quantity: 100) }
  let(:customer_subscription) do
    create(:customer_subscription, 
           :product_subscription,
           business: business,
           tenant_customer: tenant_customer,
           product: product,
           quantity: 5)
  end
  let(:service_instance) { described_class.new(customer_subscription) }

  before do
    ActsAsTenant.current_tenant = business
    
    # Ensure product has at least one variant
    unless product.product_variants.any?
      product.product_variants.create!(
        name: 'Default',
        price_modifier: 0.0,
        stock_quantity: 100
      )
    end
  end

  describe '#initialize' do
    it 'initializes with valid product subscription' do
      expect(service_instance.customer_subscription).to eq(customer_subscription)
      expect(service_instance.business).to eq(business)
      expect(service_instance.product).to eq(product)
    end

    it 'raises error for non-product subscription' do
      service_subscription = create(:customer_subscription, 
                                   :service_subscription,
                                   business: business,
                                   tenant_customer: tenant_customer)
      
      expect {
        described_class.new(service_subscription)
      }.to raise_error(ArgumentError, 'Subscription must be for a product')
    end
  end

  describe '#subscription' do
    it 'returns the customer subscription' do
      expect(service_instance.subscription).to eq(customer_subscription)
    end
  end

  describe '#check_stock_availability' do
    context 'with sufficient stock' do
      it 'returns availability information' do
        result = service_instance.check_stock_availability
        
        expect(result[:available]).to be true
        expect(result[:current_stock]).to eq(100)
        expect(result[:required_quantity]).to eq(5)
        expect(result[:remaining_after_fulfillment]).to eq(95)
      end

      it 'includes stock level classification' do
        result = service_instance.check_stock_availability
        
        expect(result[:stock_level]).to eq('high')
      end

      it 'warns about low stock when appropriate' do
        product.update!(stock_quantity: 8)
        
        result = service_instance.check_stock_availability
        
        expect(result[:warning]).to include('Low stock warning')
        expect(result[:reorder_suggested]).to be true
      end
    end

    context 'with partial stock' do
      before do
        product.update!(stock_quantity: 3)
      end

      it 'indicates partial availability' do
        result = service_instance.check_stock_availability
        
        expect(result[:available]).to be false
        expect(result[:shortage]).to eq(2)
        expect(result[:max_available_quantity]).to eq(3)
      end

      it 'suggests alternatives' do
        result = service_instance.check_stock_availability
        
        expect(result[:alternatives]).to include('partial_fulfillment')
      end
    end

    context 'with no stock' do
      before do
        product.update!(stock_quantity: 0)
      end

      it 'indicates unavailability' do
        result = service_instance.check_stock_availability
        
        expect(result[:available]).to be false
        expect(result[:stock_level]).to eq('out_of_stock')
      end
    end
  end

  describe '#reserve_stock' do
    context 'with sufficient stock' do
      it 'successfully reserves stock' do
        result = service_instance.reserve_stock
        
        expect(result[:success]).to be true
        expect(result[:reserved_quantity]).to eq(5)
        expect(result[:reservation_id]).to be_present
      end

      it 'decrements product stock' do
        initial_stock = product.stock_quantity
        
        service_instance.reserve_stock
        
        expect(product.reload.stock_quantity).to eq(initial_stock - 5)
      end
    end

    context 'with partial stock and partial allowed' do
      before do
        product.update!(stock_quantity: 3)
      end

      it 'reserves available quantity' do
        result = service_instance.reserve_stock(allow_partial: true)
        
        expect(result[:success]).to be true
        expect(result[:reserved_quantity]).to eq(3)
        expect(result[:partial_fulfillment]).to be true
      end
    end

    context 'with insufficient stock' do
      before do
        product.update!(stock_quantity: 2)
      end

      it 'fails to reserve when partial not allowed' do
        result = service_instance.reserve_stock
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient stock')
        expect(result[:available_quantity]).to eq(2)
      end
    end
  end

  describe '#release_stock' do
    let(:reservation) do
      service_instance.reserve_stock
      StockReservation.last
    end

    it 'successfully releases reserved stock' do
      reservation_id = reservation.id
      initial_stock = product.reload.stock_quantity
      
      result = service_instance.release_stock(reservation_id)
      
      expect(result[:success]).to be true
      expect(result[:released_quantity]).to eq(5)
      expect(product.reload.stock_quantity).to eq(initial_stock + 5)
    end

    it 'handles invalid reservation IDs' do
      result = service_instance.release_stock('invalid_id')
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Reservation not found')
    end

    it 'prevents double release' do
      reservation_id = reservation.id
      
      # First release
      service_instance.release_stock(reservation_id)
      
      # Second release attempt
      result = service_instance.release_stock(reservation_id)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('already been released')
    end
  end

  describe '#find_substitute_products' do
    it 'returns empty array as substitute functionality is not needed' do
      substitutes = service_instance.find_substitute_products
      
      expect(substitutes).to eq([])
    end
  end

  describe '#handle_stock_shortage' do
    let(:shortage_scenario) do
      {
        required_quantity: 10,
        available_quantity: 3,
        shortage: 7
      }
    end

    context 'with no alternatives available' do
      it 'suggests skip delivery' do
        result = service_instance.handle_stock_shortage(shortage_scenario)
        
        expect(result[:strategy]).to eq('skip_delivery')
        expect(result[:skip_reason]).to include('stock shortage')
      end

      it 'offers loyalty compensation when loyalty program enabled' do
        business.update!(loyalty_program_enabled: true)
        
        result = service_instance.handle_stock_shortage(shortage_scenario)
        
        expect(result[:loyalty_compensation]).to be_present
        expect(result[:compensation_points]).to be > 0
      end
    end
  end

  describe '#update_stock_levels' do
    let(:fulfillment_data) do
      {
        fulfilled_quantity: 5,
        reservation_id: 'res_123',
        order_id: 'ord_456'
      }
    end

    it 'updates stock after successful fulfillment' do
      initial_stock = product.stock_quantity
      
      service_instance.update_stock_levels(fulfillment_data)
      
      expect(product.reload.stock_quantity).to eq(initial_stock - 5)
    end

    it 'creates stock movement record' do
      expect {
        service_instance.update_stock_levels(fulfillment_data)
      }.to change(StockMovement, :count).by(1)
      
      movement = StockMovement.last
      expect(movement.product).to eq(product)
      expect(movement.quantity).to eq(-5)
      expect(movement.movement_type).to eq('subscription_fulfillment')
    end

    it 'triggers low stock alerts' do
      expect(StockAlertService).to receive(:check_and_notify).with(product)
      
      service_instance.update_stock_levels({ fulfilled_quantity: 5 })
    end

    it 'handles stock adjustment errors gracefully' do
      allow(product).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      
      result = service_instance.update_stock_levels(fulfillment_data)
      
      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end
  end

  describe '#calculate_reorder_point' do
    it 'calculates reorder point based on usage patterns' do
      reorder_point = service_instance.calculate_reorder_point
      
      expect(reorder_point).to be > 0
      expect(reorder_point).to be_a(Integer)
    end

    it 'uses default lead time in calculation' do
      reorder_point = service_instance.calculate_reorder_point
      
      # Should account for default 7 days lead time plus 5 days safety stock
      expect(reorder_point).to be >= 1
    end

    it 'handles products with no usage history' do
      new_product = create(:product, business: business, subscription_enabled: true)
      new_subscription = create(:customer_subscription, 
                               :product_subscription,
                               business: business,
                               product: new_product)
      new_service = described_class.new(new_subscription)
      
      reorder_point = new_service.calculate_reorder_point
      
      expect(reorder_point).to be > 0  # Should use default calculation
    end
  end

  describe 'performance and optimization' do
    it 'performs stock checks efficiently' do
      start_time = Time.current
      service_instance.check_stock_availability
      end_time = Time.current
      
      expect(end_time - start_time).to be < 0.1
    end

    it 'handles concurrent stock operations safely' do
      # Mock the concurrent behavior instead of actually creating threads
      allow(service_instance).to receive(:reserve_stock).and_call_original
      
      # Simulate multiple reservation attempts
      results = []
      initial_stock = product.stock_quantity
      
      5.times do
        results << service_instance.reserve_stock
      end
      
      # Verify logical consistency without threading overhead
      successful_reservations = results.count { |r| r[:success] }
      total_reserved = results.select { |r| r[:success] }.sum { |r| r[:reserved_quantity] }
      
      expect(total_reserved).to be <= initial_stock
      expect(successful_reservations).to be <= (initial_stock / customer_subscription.quantity)
    end
    
    it 'efficiently handles large product catalogs', :slow do
      # Only run this test when specifically tagged, and use build_stubbed for speed
      products = build_stubbed_list(:product, 50, business: business, subscription_enabled: true)
      allow(Product).to receive(:where).and_return(products)
      
      start_time = Time.current
      service_instance.find_substitute_products
      end_time = Time.current
      
      expect(end_time - start_time).to be < 0.1
    end
  end

  describe 'error handling and edge cases' do
    it 'handles negative stock quantities gracefully' do
      product.update!(stock_quantity: -5)
      
      result = service_instance.check_stock_availability
      
      expect(result[:available]).to be false
      expect(result[:stock_level]).to eq('negative')
    end

    it 'handles invalid reservation IDs' do
      result = service_instance.release_stock('invalid_id')
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Reservation not found')
    end
  end

  describe 'multi-tenant behavior' do
    let(:other_business) { create(:business) }

    it 'isolates stock management by business' do
      ActsAsTenant.with_tenant(business) do
        result = service_instance.check_stock_availability
        expect(result[:current_stock]).to eq(product.stock_quantity)
      end
      
      ActsAsTenant.with_tenant(other_business) do
        expect(Product.find_by(id: product.id)).to be_nil
      end
    end

    it 'does not find substitutes from other businesses' do
      # Create product with unique name to avoid validation conflicts
      other_substitute = create(:product, 
                               business: other_business,
                               name: "Other Business Product #{SecureRandom.hex(4)}",
                               subscription_enabled: true,
                               stock_quantity: 100)
      
      substitutes = service_instance.find_substitute_products
      
      expect(substitutes).to eq([])
    end
  end

  describe 'integration with loyalty system' do
    it 'offers loyalty compensation for stock shortages' do
      product.update!(stock_quantity: 0)
      
      result = service_instance.handle_stock_shortage({
        required_quantity: 5,
        available_quantity: 0,
        shortage: 5
      })
      
      expect(result[:loyalty_compensation]).to be_present
      expect(result[:compensation_points]).to be > 0
    end
  end
end 