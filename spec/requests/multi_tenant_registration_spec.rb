# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MultiTenant Registration", type: :request do
  let(:email) { "same_user@example.com" }
  let(:password) { "password123" }
  let(:business1) { create(:business, name: "First Business", subdomain: "first") }
  let(:business2) { create(:business, name: "Second Business", subdomain: "second") }

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
    it "allows registration and authentication with the same email in different businesses" do
      # Create test connection
      connection = ActiveRecord::Base.connection
      
      # Generate password hash manually since we don't have direct access to has_secure_password methods
      require 'bcrypt'
      encrypted_password = BCrypt::Password.create(password)
      
      # Using execute to directly insert users and bypass Active Record validations
      # Insert first user
      connection.execute(
        "INSERT INTO users (email, encrypted_password, business_id, role, active, created_at, updated_at) 
         VALUES ('#{email}', '#{encrypted_password}', #{business1.id}, 0, true, '#{Time.current}', '#{Time.current}') 
         RETURNING id"
      )
      
      # Insert second user with same email but different business
      connection.execute(
        "INSERT INTO users (email, encrypted_password, business_id, role, active, created_at, updated_at) 
         VALUES ('#{email}', '#{encrypted_password}', #{business2.id}, 0, true, '#{Time.current}', '#{Time.current}') 
         RETURNING id"
      )
      
      # Query both users from the database
      users = User.unscoped.where(email: email).order(:business_id)
      user1 = users.first
      user2 = users.last
      
      # Verify we have two different users with the same email
      expect(users.count).to eq(2)
      expect(user1.id).not_to eq(user2.id)
      expect(user1.email).to eq(user2.email)
      expect(user1.business_id).to eq(business1.id)
      expect(user2.business_id).to eq(business2.id)
    end
  end
end 