require 'rails_helper'

RSpec.describe "business_manager/orders/index.html.erb", type: :view do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }

  before do
    ActsAsTenant.current_tenant = business
    assign(:current_business, business)
    
    # Create some test orders with different types, ensure order number is present
    product_order = create(:order, business: business, tenant_customer: tenant_customer, order_type: :product, status: 'pending_payment', order_number: 'P123')
    service_order = create(:order, business: business, tenant_customer: tenant_customer, order_type: :service, status: 'paid', order_number: 'S456')
    
    # Assign for the view
    assign(:orders, [product_order, service_order])
    
    # Stub flash messages
    allow(view).to receive(:flash).and_return({})
    
    # Set up request path helpers
    allow(view).to receive(:business_manager_orders_path).and_return('/manage/orders')
    allow(view).to receive(:business_manager_order_path).and_return('/manage/orders/1') # Generic path for any order link
    allow(view).to receive(:business_manager_dashboard_path).and_return('/manage/dashboard')
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it "displays a list of orders" do
    render
    
    # Debug: Output rendered HTML
    puts "\n--- Rendered HTML (Index Spec) ---\n"
    puts rendered
    puts "---\n"
    
    # Page title/header
    expect(rendered).to have_content('Business Orders')
    
    # Columns
    expect(rendered).to have_selector('th', text: 'Order Number')
    expect(rendered).to have_selector('th', text: 'Date')
    expect(rendered).to have_selector('th', text: 'Customer')
    expect(rendered).to have_selector('th', text: 'Status')
    expect(rendered).to have_selector('th', text: 'Type')
    expect(rendered).to have_selector('th', text: 'Total')
    expect(rendered).to have_selector('th', text: 'Actions')
    
    # Orders content
    view.instance_variable_get(:@orders).each do |order|
      # Debug: Output order number      
      # Check for the entire row content or specific cells
      # Checking for the link text within a td is a robust approach
      expect(rendered).to have_content(order.order_number)
      expect(rendered).to have_content(order.tenant_customer.name)
      
      # Status badge - look for spans with status text instead of specific class
      expect(rendered).to have_selector('span', text: order.status.titleize)
      
      # Type badge - look for spans with type text instead of specific class
      expect(rendered).to have_selector('span', text: order.order_type.titleize)
    end
  end

  it "displays filter options" do
    render
    
    # Filter sections
    expect(rendered).to have_content('Filter by Status')
    expect(rendered).to have_content('Filter by Type')
    
    # Status filters 
    expect(rendered).to have_link('All', href: business_manager_orders_path(type: nil, status: nil))
    Order.statuses.keys.each do |status|
      expect(rendered).to have_link(status.titleize)
    end
    
    # Type filters
    expect(rendered).to have_link('All', href: business_manager_orders_path(type: nil, status: nil))
    Order.order_types.keys.each do |type|
      expect(rendered).to have_link(type.titleize)
    end
  end

  it "displays empty state when no orders" do
    assign(:orders, [])
    render
    
    expect(rendered).to have_content('No orders found')
  end

  it "links back to dashboard" do
    render
    expect(rendered).to have_link('Back to Dashboard', href: business_manager_dashboard_path)
  end
end 