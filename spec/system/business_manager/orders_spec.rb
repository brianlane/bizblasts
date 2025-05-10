require 'rails_helper'

RSpec.describe "Business Manager Orders", type: :system do
  let!(:business) { create(:business, name: "Test Business") }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, name: "Test Customer") }
  
  # Create different types of orders
  let!(:product_order) do
    create(:order, 
      business: business, 
      tenant_customer: tenant_customer, 
      order_type: :product, 
      status: 'pending',
      line_items_count: 2,
      total_amount: 49.99
    )
  end
  
  let!(:service_order) do
    create(:order, 
      business: business, 
      tenant_customer: tenant_customer, 
      order_type: :service, 
      status: 'completed',
      line_items_count: 1,
      total_amount: 75.00
    )
  end
  
  let!(:mixed_order) do
    create(:order, 
      business: business, 
      tenant_customer: tenant_customer, 
      order_type: :mixed, 
      status: 'shipped',
      line_items_count: 3,
      total_amount: 120.50
    )
  end

  before do
    # Set up Capybara to use the business's subdomain
    Capybara.app_host = "http://#{business.hostname}.lvh.me"
    
    # Log in as the business manager
    visit new_user_session_path
    fill_in "Email", with: manager.email
    fill_in "Password", with: manager.password
    click_button "Log in"
  end

  describe "viewing orders from dashboard" do
    it "navigates to orders index from dashboard" do
      visit business_manager_dashboard_path
      
      # Find and click the "View Orders" link in the quick actions section
      within "#quick-actions-widget" do
        click_link "View Orders"
      end
      
      # Verify we're on the orders index page
      expect(page).to have_current_path(business_manager_orders_path)
      expect(page).to have_content("Business Orders")
    end
  end

  describe "orders index page" do
    before do
      visit business_manager_orders_path
    end

    it "displays a list of all orders" do
      expect(page).to have_content("Business Orders")
      
      # Check that all orders are displayed
      expect(page).to have_content(product_order.order_number)
      expect(page).to have_content(service_order.order_number)
      expect(page).to have_content(mixed_order.order_number)
      
      # Verify status badges
      expect(page).to have_css(".status-badge", text: "Pending")
      expect(page).to have_css(".status-badge", text: "Completed")
      expect(page).to have_css(".status-badge", text: "Shipped")
      
      # Verify type badges
      expect(page).to have_css(".type-badge", text: "Product")
      expect(page).to have_css(".type-badge", text: "Service")
      expect(page).to have_css(".type-badge", text: "Mixed")
    end

    it "filters orders by type" do
      # Click on the Product filter
      within ".filter-group", text: "Filter by Type" do
        click_link "Product"
      end
      
      # Verify only product orders are shown
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
      
      # Now try service filter
      within ".filter-group", text: "Filter by Type" do
        click_link "Service"
      end
      
      # Verify only service orders are shown
      expect(page).not_to have_content(product_order.order_number)
      expect(page).to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
    end

    it "filters orders by status" do
      # Click on the Pending filter
      within ".filter-group", text: "Filter by Status" do
        click_link "Pending"
      end
      
      # Verify only pending orders are shown
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
    end
    
    it "combines status and type filters" do
      # Apply status filter first
      within ".filter-group", text: "Filter by Status" do
        click_link "Pending"
      end
      
      # Then apply type filter
      within ".filter-group", text: "Filter by Type" do
        click_link "Product"
      end
      
      # Verify the combined filter shows the correct order
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
      
      # The URL should include both filters
      uri = URI.parse(current_url)
      params = CGI.parse(uri.query || "")
      expect(params["status"]).to eq(["pending"])
      expect(params["type"]).to eq(["product"])
    end
    
    it "returns to dashboard when clicking back link" do
      click_link "← Back to Dashboard"
      expect(page).to have_current_path(business_manager_dashboard_path)
    end
  end

  describe "order details page" do
    it "navigates to order details from index" do
      visit business_manager_orders_path
      
      # Click on an order number
      click_link product_order.order_number
      
      # Verify we're on the correct order detail page
      expect(page).to have_current_path(business_manager_order_path(product_order))
      expect(page).to have_content("Order Details: #{product_order.order_number}")
    end
    
    it "displays order details correctly" do
      visit business_manager_order_path(product_order)
      
      # Check basic order information
      expect(page).to have_content(product_order.order_number)
      expect(page).to have_content("Product") # order type
      expect(page).to have_content("Pending") # status
      expect(page).to have_content(tenant_customer.name)
      
      # Check line items
      expect(page).to have_content("Items:")
      product_order.line_items.each do |item|
        expect(page).to have_content(item.product_variant.product.name)
      end
      
      # Check financial summary
      expect(page).to have_content("Financial Summary:")
      expect(page).to have_content("$#{sprintf('%.2f', product_order.total_amount)}")
    end
    
    it "navigates back to the orders list" do
      visit business_manager_order_path(product_order)
      
      click_link "Back to Business Orders"
      expect(page).to have_current_path(business_manager_orders_path)
    end
  end
end 