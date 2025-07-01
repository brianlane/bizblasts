require 'rails_helper'

RSpec.describe 'business_manager/products/show.html.erb', type: :view do
  let(:business) { create(:business) }
  let(:product) { create(:product, business: business) }

  before do
    assign(:product, product)
    allow(view).to receive(:current_business).and_return(business)
  end

  it 'renders the product show page without errors' do
    expect { render }.not_to raise_error
  end

  context 'when stock management is enabled' do
    before do
      business.update!(stock_management_enabled: true)
    end

    it 'shows stock information' do
      render
      expect(rendered).to include('Stock')
      expect(rendered).to include('Stock Visibility')
    end
  end

  context 'when stock management is disabled' do
    before do
      business.update!(stock_management_enabled: false)
    end

    it 'shows always available information' do
      render
      expect(rendered).to include('Always Available')
      expect(rendered).to include('Stock tracking disabled for this business')
    end
  end
end 