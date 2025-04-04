# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantCustomer, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business).required }
    it { is_expected.to have_many(:bookings) }
  end

  describe 'validations' do
    it 'validates presence of name' do
      customer = TenantCustomer.new(email: 'test@example.com', phone: '555-123-4567')
      expect(customer).not_to be_valid
      expect(customer.errors[:name]).to include("can't be blank")
    end
    
    it 'validates uniqueness of email scoped to business_id' do
      # Create a business for testing
      business = Business.create!(name: "Test Business", subdomain: "test#{Time.now.to_i}")
      
      # Create a customer with this business
      existing = TenantCustomer.create!(
        name: "Existing Customer",
        email: "same@example.com",
        phone: "555-123-4567",
        business: business
      )
      
      # Attempt to create another customer with the same email in the same business
      duplicate = TenantCustomer.new(
        name: "Another Customer",
        email: "same@example.com",
        phone: "555-987-6543",
        business: business
      )
      
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("must be unique within this business")
    end
    
    it 'allows duplicate emails across different businesses' do
      # Create two distinct businesses
      business1 = Business.create!(
        name: "Business 1",
        subdomain: "biz1#{Time.now.to_i}"
      )
      
      business2 = Business.create!(
        name: "Business 2",
        subdomain: "biz2#{Time.now.to_i}"
      )
      
      # Create a customer in the first business
      TenantCustomer.create!(
        name: "Customer in Business 1",
        email: "duplicate@example.com",
        phone: "555-123-4567",
        business: business1
      )
      
      # Create a customer with the same email in a different business
      customer2 = TenantCustomer.new(
        name: "Customer in Business 2",
        email: "duplicate@example.com",
        phone: "555-987-6543",
        business: business2
      )
      
      # Should be valid since it's in a different business
      expect(customer2).to be_valid
    end
  end
end 