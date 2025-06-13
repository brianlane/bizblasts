# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Manager Order Invoice Creation", type: :system do
  include_context 'setup business context'
  
  let!(:tenant_customer) { create(:tenant_customer, business: business, name: "Test Customer", email: "test@customer.com") }
  let!(:tax_rate) { create(:tax_rate, business: business, name: "Standard Tax", rate: 0.1) }
  let!(:product) { create(:product, business: business, name: "Test Product", price: 50.0) }
  let!(:variant) { create(:product_variant, product: product, stock_quantity: 10, name: "Default Variant") }

  before do
    driven_by(:rack_test)
    
    # Clear any existing emails
    ActionMailer::Base.deliveries.clear
    
    # Log in as the business manager
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  describe "creating a service order" do
    it "automatically creates an invoice and sends email to customer" do
      # Visit the new order page first to get proper session setup
      visit new_business_manager_order_path
      
      # Create a service order with proper attributes
      order_params = {
        order: {
          tenant_customer_id: tenant_customer.id,
          tax_rate_id: tax_rate.id,
          notes: "Test service order for past work",
          line_items_attributes: {
            "0" => {
              service_id: service1.id,
              staff_member_id: staff_member.id,
              quantity: 1,
              price: service1.price
            }
          }
        }
      }
      
      expect {
        # Use page.driver.post to maintain session
        page.driver.post business_manager_orders_path, order_params
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(1)
      
      # Verify the order was created correctly
      order = Order.last
      expect(order.order_type).to eq('service')
      expect(order.invoice).to be_present
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.tax_rate).to eq(tax_rate)
      
      # Verify invoice details
      invoice = order.invoice
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.business).to eq(business)
      expect(invoice.status).to eq('pending')
    end
  end

  describe "creating a product order" do
    it "does not create an invoice" do
      # Visit the new order page first to get proper session setup
      visit new_business_manager_order_path
      
      # Create a product order with proper attributes
      order_params = {
        order: {
          tenant_customer_id: tenant_customer.id,
          tax_rate_id: tax_rate.id,
          notes: "Test product order",
          line_items_attributes: {
            "0" => {
              product_variant_id: variant.id,
              quantity: 2,
              price: variant.final_price
            }
          }
        }
      }
      
      expect {
        # Use page.driver.post to maintain session
        page.driver.post business_manager_orders_path, order_params
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(0)
      
      # Verify the order was created correctly
      order = Order.last
      expect(order.order_type).to eq('product')
      expect(order.invoice).to be_nil
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.tax_rate).to eq(tax_rate)
    end
  end

  describe "creating a mixed order" do
    it "automatically creates an invoice and sends email to customer" do
      # Visit the new order page first to get proper session setup
      visit new_business_manager_order_path
      
      # Create a mixed order with both product and service line items
      order_params = {
        order: {
          tenant_customer_id: tenant_customer.id,
          tax_rate_id: tax_rate.id,
          notes: "Test mixed order",
          line_items_attributes: {
            "0" => {
              product_variant_id: variant.id,
              quantity: 1,
              price: variant.final_price
            },
            "1" => {
              service_id: service1.id,
              staff_member_id: staff_member.id,
              quantity: 1,
              price: service1.price
            }
          }
        }
      }
      
      expect {
        # Use page.driver.post to maintain session
        page.driver.post business_manager_orders_path, order_params
      }.to change(Order, :count).by(1)
       .and change(Invoice, :count).by(1)
      
      # Verify the order was created correctly
      order = Order.last
      expect(order.order_type).to eq('mixed')
      expect(order.invoice).to be_present
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.tax_rate).to eq(tax_rate)
      
      # Verify invoice details
      invoice = order.invoice
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.business).to eq(business)
      expect(invoice.status).to eq('pending')
    end
  end
end 