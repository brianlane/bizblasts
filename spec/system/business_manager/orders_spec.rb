require 'rails_helper'

RSpec.describe "Business Manager Orders", type: :system do
  let!(:business) { create(:business, name: "Test Business") }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, first_name: "Test", last_name: "Customer") }
  
  # Create different types of orders
  let!(:product_order) do
    create(:order, 
      business: business, 
      tenant_customer: tenant_customer, 
      order_type: :product, 
      status: 'pending_payment',
      line_items_count: 2,
      total_amount: 49.99
    )
  end
  
  let!(:service_order) do
    create(:order, 
      business: business, 
      tenant_customer: tenant_customer, 
      order_type: :service, 
      status: 'paid',
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
    visit '/users/sign_in'
    fill_in 'Email', with: manager.email
    fill_in 'Password', with: 'password123'
    click_button "Sign In"
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
      
      # Verify status badges (using tailwind classes)
      expect(page).to have_css("span.inline-flex", text: "Pending Payment")
      expect(page).to have_css("span.inline-flex", text: "Paid")
      expect(page).to have_css("span.inline-flex", text: "Shipped")
      
      # Verify type badges (using tailwind classes)
      expect(page).to have_css("span.inline-flex", text: "Product")
      expect(page).to have_css("span.inline-flex", text: "Service")
      expect(page).to have_css("span.inline-flex", text: "Mixed")
    end

    it "filters orders by type" do
      # Click on the Product filter - find the section with the h3 containing "Filter by Type"
      type_section = find("h3", text: "Filter by Type").find(:xpath, "..")
      within type_section do
        click_link "Product"
      end
      
      # Verify only product orders are shown
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
      
      # Now try service filter
      type_section = find("h3", text: "Filter by Type").find(:xpath, "..")
      within type_section do
        click_link "Service"
      end
      
      # Verify only service orders are shown
      expect(page).not_to have_content(product_order.order_number)
      expect(page).to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
    end

    it "filters orders by status" do
      # Click on the Pending Payment filter - find the section with the h3 containing "Filter by Status"
      status_section = find("h3", text: "Filter by Status").find(:xpath, "..")
      within status_section do
        click_link "Pending Payment"
      end
      
      # Verify only pending payment orders are shown
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
    end
    
    it "combines status and type filters" do
      # Apply status filter first
      status_section = find("h3", text: "Filter by Status").find(:xpath, "..")
      within status_section do
        click_link "Pending Payment"
      end
      
      # Then apply type filter
      type_section = find("h3", text: "Filter by Type").find(:xpath, "..")
      within type_section do
        click_link "Product"
      end
      
      # Verify the combined filter shows the correct order
      expect(page).to have_content(product_order.order_number)
      expect(page).not_to have_content(service_order.order_number)
      expect(page).not_to have_content(mixed_order.order_number)
      
      # The URL should include both filters
      uri = URI.parse(current_url)
      params = CGI.parse(uri.query || "")
      expect(params["status"]).to eq(["pending_payment"])
      expect(params["type"]).to eq(["product"])
    end
    
    it "returns to dashboard when clicking back link" do
      click_link "Back to Dashboard"
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
      expect(page).to have_content("Pending Payment") # status
      expect(page).to have_content(tenant_customer.full_name)
      
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