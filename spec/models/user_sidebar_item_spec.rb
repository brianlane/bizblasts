require 'rails_helper'

RSpec.describe UserSidebarItem, type: :model do
  describe '.default_items_for' do
    let(:user) { create(:user, role: :manager, business: business) }

    context 'when business has no products' do
      let(:business) { create(:business) }

      it 'excludes shipping_methods from default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).not_to include('shipping_methods')
      end

      it 'excludes tax_rates from default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).not_to include('tax_rates')
      end

      it 'includes other standard items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).to include('dashboard', 'bookings', 'services', 'products')
      end
    end

    context 'when business has active products' do
      let(:business) { create(:business) }

      before do
        create(:product, business: business, active: true)
      end

      it 'includes shipping_methods in default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).to include('shipping_methods')
      end

      it 'includes tax_rates in default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).to include('tax_rates')
      end
    end

    context 'when business has only inactive products' do
      let(:business) { create(:business) }

      before do
        create(:product, business: business, active: false)
      end

      it 'excludes shipping_methods from default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).not_to include('shipping_methods')
      end

      it 'excludes tax_rates from default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).not_to include('tax_rates')
      end
    end

    context 'when business tier is free' do
      let(:business) { create(:business, tier: :free) }

      it 'excludes website_builder from default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).not_to include('website_builder')
      end
    end

    context 'when business tier is premium' do
      let(:business) { create(:business, tier: :premium) }

      it 'includes website_builder in default items' do
        items = described_class.default_items_for(user)
        expect(items.map { |i| i[:key] }).to include('website_builder')
      end
    end
  end

  describe 'validations' do
    subject { build(:user_sidebar_item) }

    it { is_expected.to validate_presence_of(:item_key) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end
end
