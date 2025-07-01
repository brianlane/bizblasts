require 'rails_helper'

RSpec.describe 'business_manager/products/index.html.erb', type: :view do
  let(:business) { create(:business, stock_management_enabled: true) }
  let(:user) { create(:user, business: business) }

  before do
    assign(:products, [])
    allow(view).to receive(:current_business).and_return(business)
    allow(view).to receive(:current_user).and_return(user)
  end

  context 'when stock management is enabled' do
    it 'renders the inventory management component with enabled status' do
      render

      expect(rendered).to include('Inventory Management')
      expect(rendered).to include('Stock Tracking Enabled')
      expect(rendered).to include('Products show stock quantities and availability limits')
      expect(rendered).to include('Manage Settings')
    end

    it 'does not show the unlimited inventory warning' do
      render

      expect(rendered).not_to include('Unlimited Inventory Mode')
    end
  end

  context 'when stock management is disabled' do
    before do
      business.update!(stock_management_enabled: false)
    end

    it 'renders the inventory management component with disabled status' do
      render

      expect(rendered).to include('Inventory Management')
      expect(rendered).to include('Unlimited Inventory')
      expect(rendered).to include('All products are treated as always available')
      expect(rendered).to include('Manage Settings')
    end

    it 'shows the unlimited inventory mode warning' do
      render

      expect(rendered).to include('Unlimited Inventory Mode')
      expect(rendered).to include('Stock quantities are hidden from customers')
    end
  end

  context 'with products' do
    let!(:product) { create(:product, business: business, stock_quantity: 10) }

    before do
      assign(:products, [product])
    end

    context 'when stock management is enabled' do
      it 'shows stock information in the table' do
        render

        expect(rendered).to include('Stock')
        expect(rendered).to include('In Stock')
      end
    end

    context 'when stock management is disabled' do
      before do
        business.update!(stock_management_enabled: false)
      end

      it 'shows always available status' do
        render

        expect(rendered).to include('Always Available')
      end
    end
  end
end 