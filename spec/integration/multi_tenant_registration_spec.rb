# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MultiTenant Email Uniqueness", type: :request do
  it "ensures email uniqueness is now global" do
    # Verify that the database constraint is now global (unique index on just email)
    connection = ActiveRecord::Base.connection
    indices = connection.indexes(:users)
    email_index = indices.find { |i| i.name == 'index_users_on_email_unique' }
    
    # Verify that we have the right index structure
    expect(email_index).to be_present
    expect(email_index.columns).to eq(['email']) # Should only be email now
    expect(email_index.unique).to be true
    
    # Test that the database constraint prevents duplicate emails
    email = "test_user@example.com"
    business1 = create(:business)
    business2 = create(:business)
    
    # Insert first user (can be client, no business_id needed for DB insert)
    require 'bcrypt'
    encrypted_password = BCrypt::Password.create('password123')
    user1_id = connection.exec_query(
      "INSERT INTO users (email, encrypted_password, role, active, created_at, updated_at) 
       VALUES ('#{email}', '#{encrypted_password}', 3, true, NOW(), NOW()) RETURNING id"
    ).first['id']
    
    # Now try to insert a second user with the same email, even with a different business_id
    expect {
      connection.exec_query(
        "INSERT INTO users (email, encrypted_password, business_id, role, active, created_at, updated_at) 
         VALUES ('#{email}', '#{encrypted_password}', #{business2.id}, 1, true, NOW(), NOW()) RETURNING id"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique) # Expect a unique constraint violation
  end
end 