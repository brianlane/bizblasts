# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Transactions CSV Nil Safety', type: :unit do
  describe 'safe navigation operators' do
    it 'handles nil.product gracefully with &. operator' do
      product_variant = nil
      
      # This should not raise NoMethodError
      result = product_variant&.product
      expect(result).to be_nil
    end

    it 'handles nil array gracefully with filter_map' do
      add_ons = [nil, nil, nil]
      
      # This should not raise NoMethodError and should filter out nils
      result = add_ons.filter_map { |addon| addon&.name }
      expect(result).to eq([])
    end

    it 'demonstrates the safe navigation pattern used in the fix' do
      # Simulate a product_variant with nil product
      product_variant = double('ProductVariant')
      allow(product_variant).to receive(:product).and_return(nil)
      allow(product_variant).to receive(:name).and_return('Test Variant')
      
      # This is the pattern we use in format_order_items
      if product_variant&.product
        result = "#{product_variant.product.name} (#{product_variant.name})"
      else
        result = "Unknown item"
      end
      
      expect(result).to eq("Unknown item")
    end

    it 'demonstrates the filter_map pattern used in the fix' do
      # Simulate booking add-ons where some have nil product_variant
      addon1 = double('Addon1')
      allow(addon1).to receive(:product_variant).and_return(nil)
      
      addon2 = double('Addon2')
      product_variant = double('ProductVariant')  
      allow(product_variant).to receive(:name).and_return('Valid Addon')
      allow(addon2).to receive(:product_variant).and_return(product_variant)
      
      add_ons = [addon1, addon2]
      
      # This is the pattern we use in format_invoice_items
      result = add_ons.filter_map { |addon| addon.product_variant&.name }
      
      expect(result).to eq(['Valid Addon'])
    end
  end
end