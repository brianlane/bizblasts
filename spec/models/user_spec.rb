# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  before(:each) do
    # Clear any potential tenant to prevent test pollution
    ActsAsTenant.current_tenant = nil
  end

  describe 'validations' do
    it 'requires an email' do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
    end
    
    it 'requires a password' do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
    end
    
    it 'requires a company' do
      user = build(:user, company: nil)
      expect(user).not_to be_valid
      expect(user.errors[:company]).to include("must exist")
    end
  end
  
  describe 'email uniqueness' do
    it 'prevents duplicate emails within the same company' do
      company = create(:company)
      
      create(:user, email: 'duplicate@example.com', company: company)
      second_user = build(:user, email: 'duplicate@example.com', company: company)
      
      expect(second_user).not_to be_valid
      expect(second_user.errors[:email]).to include("has already been taken")
    end
  end
  
  describe 'acts_as_tenant integration' do
    it 'scopes queries to the current tenant' do
      # Create two companies
      company1 = create(:company, name: 'Company 1')
      company2 = create(:company, name: 'Company 2')
      
      # Create users in both companies
      user1 = create(:user, company: company1)
      user2 = create(:user, company: company2)
      
      # When tenant is company1, we should only see users from company1
      ActsAsTenant.current_tenant = company1
      expect(User.all).to include(user1)
      expect(User.all).not_to include(user2)
      
      # When tenant is company2, we should only see users from company2
      ActsAsTenant.current_tenant = company2
      expect(User.all).to include(user2)
      expect(User.all).not_to include(user1)
      
      # Reset tenant for cleanup
      ActsAsTenant.current_tenant = nil
    end
  end

  describe 'multi-tenant validations' do
    # This functionality is now tested in the integration test
    # spec/integration/multi_tenant_registration_spec.rb
    
    it 'validates that emails are unique within a company' do
      company = create(:company)
      create(:user, email: 'test@example.com', company: company)
      
      # Try to create another user with the same email in the same company
      user2 = build(:user, email: 'test@example.com', company: company)
      expect(user2).not_to be_valid
      expect(user2.errors[:email]).to include('has already been taken')
    end
  end
end 