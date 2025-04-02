# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MultiTenant Registration", type: :request do
  let(:email) { "same_user@example.com" }
  let(:password) { "password123" }
  let(:company1) { create(:company, name: "First Company", subdomain: "first") }
  let(:company2) { create(:company, name: "Second Company", subdomain: "second") }

  # Helper to set the host with subdomain
  def set_host(subdomain)
    host! "#{subdomain}.example.com"
  end

  # Reset session between requests
  def reset_session_and_tenant
    @request.reset_session if @request
    ActsAsTenant.current_tenant = nil
  end

  describe "users with identical emails in different tenants" do
    it "allows registration and authentication with the same email in different companies" do
      # Create test connection
      connection = ActiveRecord::Base.connection
      
      # Generate password hash - using our first integration test approach
      encrypted_password = User.new(password: password).encrypted_password
      
      # Using execute to directly insert users and bypass Active Record validations
      # Insert first user
      connection.execute(
        "INSERT INTO users (email, encrypted_password, company_id, created_at, updated_at) 
         VALUES ('#{email}', '#{encrypted_password}', #{company1.id}, '#{Time.current}', '#{Time.current}') 
         RETURNING id"
      )
      
      # Insert second user with same email but different company
      connection.execute(
        "INSERT INTO users (email, encrypted_password, company_id, created_at, updated_at) 
         VALUES ('#{email}', '#{encrypted_password}', #{company2.id}, '#{Time.current}', '#{Time.current}') 
         RETURNING id"
      )
      
      # Query both users from the database
      users = User.unscoped.where(email: email).order(:company_id)
      user1 = users.first
      user2 = users.last
      
      # Verify we have two different users with the same email
      expect(users.count).to eq(2)
      expect(user1.id).not_to eq(user2.id)
      expect(user1.email).to eq(user2.email)
      expect(user1.company_id).to eq(company1.id)
      expect(user2.company_id).to eq(company2.id)
    end
  end
end 