require 'rails_helper'

RSpec.describe 'Order Form Rich Dropdowns', type: :system do
  include_context 'setup business context'
  
  let!(:product) { create(:product, business: business, price: 20.00) }
  let!(:product_variant) { create(:product_variant, product: product, price_modifier: 5.00) } # 20 + 5 = 25.00 final price
  let!(:customer) { create(:tenant_customer, business: business) }

  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  it 'displays the order form page successfully' do
    visit new_business_manager_order_path
    
    # Basic page structure checks
    expect(page.status_code).to eq(200)
    expect(page).to have_content('Customer')
    expect(page).to have_content('Tax Rate')
    
    # Check for form elements existence
    expect(page).to have_css('form')
    expect(page).to have_css('input', visible: false) # Check for any input elements (including hidden)
  end

  it 'contains product and service data in the page' do
    visit new_business_manager_order_path
    
    # Check that product and service data is available in the page structure
    expect(page.body).to include(product.name)
    expect(page.body).to include(service1.name)
    expect(page.body).to include(staff_member.name)
  end

  it 'has the necessary JavaScript templates for dynamic content' do
    visit new_business_manager_order_path
    
    # Check for table elements that would be used by JavaScript
    expect(page).to have_css('table#line-items-table')
    expect(page).to have_css('table#service-line-items-table')
    
    # Check for pricing data that JavaScript would use
    expect(page.body).to include('25.00') # Product variant final price
    expect(page.body).to include(service1.price.to_s)
  end

  it 'includes dropdown functionality structure' do
    visit new_business_manager_order_path
    
    # Check for dropdown structure elements
    expect(page).to have_css('button') # Form buttons and dropdown triggers
    expect(page).to have_css('.customer-dropdown') # Customer dropdown container
    
    # Verify customer selection mechanism exists  
    expect(page).to have_css('#order_tenant_customer_id', visible: false) # Hidden field for customer ID
  end
end 