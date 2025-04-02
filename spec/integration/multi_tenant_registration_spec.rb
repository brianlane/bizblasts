# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MultiTenant Email Uniqueness", type: :request do
  it "allows the same email to be used across different tenants when properly configured" do
    # First verify that the database constraint is properly set up
    # We should have a unique index on [company_id, email] not just email
    connection = ActiveRecord::Base.connection
    indices = connection.indexes(:users)
    email_index = indices.find { |i| i.columns.include?('email') }
    
    # Verify that we have the right index structure
    expect(email_index).to be_present
    expect(email_index.columns).to match_array(['company_id', 'email'])
    expect(email_index.unique).to be true
    
    # This part directly tests if the database allows two users with the same email
    # but different company_ids by inserting directly into the database
    email = "test_user@example.com"
    company1 = create(:company)
    company2 = create(:company)
    
    # Insert first user
    encrypted_password = Devise::Encryptor.digest(User, 'password123')
    user1_id = connection.exec_query(
      "INSERT INTO users (email, encrypted_password, company_id, created_at, updated_at) 
       VALUES ('#{email}', '#{encrypted_password}', #{company1.id}, NOW(), NOW()) RETURNING id"
    ).first['id']
    
    # Now try to insert a second user with the same email but different company
    user2_id = connection.exec_query(
      "INSERT INTO users (email, encrypted_password, company_id, created_at, updated_at) 
       VALUES ('#{email}', '#{encrypted_password}', #{company2.id}, NOW(), NOW()) RETURNING id"
    ).first['id']
    
    # If we got here without an error, it means the database constraint allowed it
    # Verify that we have two separate users
    user_records = connection.select_all(
      "SELECT id, email, company_id FROM users WHERE email = '#{email}'"
    )
    
    expect(user_records.count).to eq(2)
    expect(user_records.map { |r| r['company_id'] }).to contain_exactly(company1.id, company2.id)
  end
end 