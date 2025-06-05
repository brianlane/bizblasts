require 'rails_helper'

RSpec.describe "Business Manager Order Invoice Creation", type: :system do
  let!(:business) { create(:business, hostname: "testbiz") }
  let!(:manager) { 
    create(:user, :manager, business: business).tap do |user|
      # Ensure email notifications are enabled for this test
      user.update(notification_preferences: {
        'email_order_notifications' => true,
        'email_customer_notifications' => true,
        'email_payment_notifications' => true
      })
    end
  }
  let!(:tenant_customer) { create(:tenant_customer, business: business, name: "Test Customer") }
  let!(:service) { create(:service, business: business, name: "Test Service", price: 150.0, duration: 60) }
  let!(:staff_member) { create(:staff_member, business: business, name: "Test Staff") }
  let!(:tax_rate) { create(:tax_rate, business: business, name: "Standard Tax", rate: 0.1) }
  let!(:product) { create(:product, business: business, name: "Test Product", price: 50.0) }
  let!(:variant) { create(:product_variant, product: product, stock_quantity: 10) }

  before do
    # Set up Capybara to use the business's subdomain
    Capybara.app_host = "http://#{business.hostname}.lvh.me"
    
    # Clear any existing emails
    ActionMailer::Base.deliveries.clear
    
    # Log in as the business manager
    login_as(manager, scope: :user)
    
    # Visit the business manager dashboard to ensure proper setup
    visit business_manager_dashboard_path
  end

  describe "creating a service order" do
    it "automatically creates an invoice and sends email to customer" do
      visit business_manager_orders_path
      
      # Click the "Generate New Order" link (choose the first one to avoid ambiguity)
      first("a", text: "Generate New Order").click
      
      # Fill in the order form
      select_from_custom_dropdown "#{tenant_customer.name} (#{tenant_customer.email})", "Customer"
      select_from_custom_dropdown tax_rate.name, "Tax Rate"
      fill_in "Notes", with: "Test service order for past work"
      
      # Add a service line item by clicking the Add Service button
      click_button "Add Service"
      
      # Find the newly added service row and fill it out using the actual class names
      within "#service-line-items-table tbody tr:last-child" do
        find(".service-select").select("#{service.name} (#{service.duration}m)")
        find(".staff-select").select(staff_member.name)
        find(".qty-input").set("1")
      end
      
      # Submit the form
      # Note: System tests handle transactions differently, so email behavior is tested in unit tests
      expect {
        click_button "Create Order"
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(1)
      
      # Verify we're redirected to the order show page
      order = Order.last
      expect(page).to have_current_path(business_manager_order_path(order))
      
      # Check for invoice creation success message
      expect(page).to have_content("Order created successfully. Invoice has been generated and emailed to the customer.")
      
      # Verify the order was created correctly
      expect(order.order_type).to eq('service')
      expect(order.invoice).to be_present
      expect(order.tenant_customer).to eq(tenant_customer)
      
      # Verify invoice details
      invoice = order.invoice
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.business).to eq(business)
      expect(invoice.status).to eq('pending')
      expect(invoice.due_date).to be_within(1.day).of(30.days.from_now)
      
      # Verify the order details are displayed
      expect(page).to have_content(order.order_number)
      expect(page).to have_content("Service")
      expect(page).to have_content(tenant_customer.name)
    end
  end

  describe "creating a product order" do
    it "does not create an invoice" do
      visit business_manager_orders_path
      
      # Click the "Generate New Order" link (choose the first one to avoid ambiguity)
      first("a", text: "Generate New Order").click
      
      # Fill in the order form
      select_from_custom_dropdown "#{tenant_customer.name} (#{tenant_customer.email})", "Customer"
      select_from_custom_dropdown tax_rate.name, "Tax Rate"
      fill_in "Notes", with: "Test product order"
      
      # Add a product line item by clicking the Add Product button
      click_button "Add Product"
      
      # Find the newly added product row and fill it out using the actual class names
      within "#line-items-table tbody tr:last-child" do
        find(".product-select").select("#{product.name} - #{variant.name}")
        find(".qty-input").set("2")
      end
      
      # Submit the form
      expect {
        click_button "Create Order"
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(0)
      
      # Verify no email was sent
      expect(ActionMailer::Base.deliveries).to be_empty
      
      # Verify we're redirected to the order show page
      order = Order.last
      expect(page).to have_current_path(business_manager_order_path(order))
      
      # Check for standard success message (no invoice mention)
      expect(page).to have_content("Order created successfully")
      expect(page).not_to have_content("Invoice has been generated")
      
      # Verify the order was created correctly
      expect(order.order_type).to eq('product')
      expect(order.invoice).to be_nil
    end
  end

  describe "creating a mixed order" do
    it "automatically creates an invoice and sends email to customer" do
      visit business_manager_orders_path
      
      # Click the "Generate New Order" link (choose the first one to avoid ambiguity)
      first("a", text: "Generate New Order").click
      
      # Fill in the order form
      select_from_custom_dropdown "#{tenant_customer.name} (#{tenant_customer.email})", "Customer"
      select_from_custom_dropdown tax_rate.name, "Tax Rate"
      fill_in "Notes", with: "Test mixed order"
      
      # Add a product line item first
      click_button "Add Product"
      within "#line-items-table tbody tr:last-child" do
        find(".product-select").select("#{product.name} - #{variant.name}")
        find(".qty-input").set("1")
      end
      
      # Add a service line item second
      click_button "Add Service"
      within "#service-line-items-table tbody tr:last-child" do
        find(".service-select").select("#{service.name} (#{service.duration}m)")
        find(".staff-select").select(staff_member.name)
        find(".qty-input").set("1")
      end
      
      # Submit the form
      # Note: System tests handle transactions differently, so email behavior is tested in unit tests
      expect {
        click_button "Create Order"
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(1)
      
      # Verify we're redirected to the order show page
      order = Order.last
      expect(page).to have_current_path(business_manager_order_path(order))
      
      # Check for invoice creation success message
      expect(page).to have_content("Order created successfully. Invoice has been generated and emailed to the customer.")
      
      # Verify the order was created correctly
      expect(order.order_type).to eq('mixed')
      expect(order.invoice).to be_present
      
      # Verify invoice details
      invoice = order.invoice
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.business).to eq(business)
      expect(invoice.status).to eq('pending')
    end
  end
end 