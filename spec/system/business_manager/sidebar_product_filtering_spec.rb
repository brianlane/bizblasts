require 'rails_helper'

RSpec.describe 'Sidebar Product Filtering', type: :system do
  include_context 'setup business context'

  before do
    switch_to_subdomain(business.subdomain)
    login_as(manager, scope: :user)
  end

  context 'when business has no products' do
    it 'does not show shipping methods in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).not_to have_content('Shipping Methods')
      end
    end

    it 'does not show tax rates in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).not_to have_content('Tax Rates')
      end
    end

    it 'still shows other menu items' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).to have_content('Dashboard')
        expect(page).to have_content('Services')
        expect(page).to have_content('Products')
      end
    end
  end

  context 'when business has active products' do
    before do
      create(:product, business: business, active: true)
    end

    it 'shows shipping methods in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).to have_content('Shipping Methods')
      end
    end

    it 'shows tax rates in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).to have_content('Tax Rates')
      end
    end
  end

  context 'when business has only inactive products' do
    before do
      create(:product, business: business, active: false)
    end

    it 'does not show shipping methods in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).not_to have_content('Shipping Methods')
      end
    end

    it 'does not show tax rates in the sidebar' do
      visit business_manager_dashboard_path
      within('#sidebar') do
        expect(page).not_to have_content('Tax Rates')
      end
    end
  end
end
