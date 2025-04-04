# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:staff_member).optional }
  end

  before(:each) do
    # Clear any potential tenant to prevent test pollution
    ActsAsTenant.current_tenant = nil
  end

  describe 'validations' do
    let(:business) { create(:business) }
    subject { build(:user, business: business) }
    
    it { is_expected.to validate_presence_of(:email) }
    
    # Test uniqueness scoped to business_id
    it 'validates uniqueness of email scoped to business_id' do
      create(:user, email: 'unique@example.com', business: business)
      duplicate = build(:user, email: 'unique@example.com', business: business)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end

    it 'allows duplicate emails across different businesses' do
      business1 = create(:business)
      business2 = create(:business)
      create(:user, email: 'duplicate@example.com', business: business1)
      user2 = build(:user, email: 'duplicate@example.com', business: business2)
      expect(user2).to be_valid
    end
  end

  describe 'scopes' do
    before do
      @business = create(:business)
      @active_user = create(:user, active: true, business: @business)
      @inactive_user = create(:user, active: false, business: @business)
      @admin = create(:user, role: :admin, business: @business)
      @staff = create(:user, role: :staff, business: @business)
      @client = create(:user, role: :client, business: @business)
    end

    it '.active returns only active users' do
      expect(User.active).to include(@active_user)
      expect(User.active).not_to include(@inactive_user)
    end

    it '.staff_users returns admin, manager, and staff roles' do
      expect(User.staff_users).to include(@admin, @staff)
      expect(User.staff_users).not_to include(@client)
    end
  end

  describe 'role enum' do
    it 'defines roles' do
      expect(User.roles.keys).to include('admin', 'manager', 'staff', 'client')
    end
  end

  describe '#staff?' do
    it 'returns true for admin roles' do
      user = build(:user, role: :admin)
      expect(user.staff?).to be_truthy
    end

    it 'returns true for staff roles' do
      user = build(:user, role: :staff)
      expect(user.staff?).to be_truthy
    end

    it 'returns false for client roles' do
      user = build(:user, role: :client)
      expect(user.staff?).to be_falsey
    end
  end

  describe '#full_name' do
    it 'returns the email' do
      user = build(:user, email: 'test@example.com')
      expect(user.full_name).to eq('test@example.com')
    end
  end

  describe 'acts_as_tenant integration' do
    it 'scopes queries to the current tenant' do
      business1 = create(:business)
      business2 = create(:business)
      
      user1 = create(:user, business: business1, email: 'user@example.com')
      user2 = create(:user, business: business2, email: 'user@example.com')
      
      ActsAsTenant.with_tenant(business1) do
        expect(User.count).to eq(1)
        expect(User.first).to eq(user1)
      end
      
      ActsAsTenant.with_tenant(business2) do
        expect(User.count).to eq(1)
        expect(User.first).to eq(user2)
      end
    end
  end

  describe 'multi-tenant validations' do
    # This functionality is now tested in the integration test
    # spec/integration/multi_tenant_registration_spec.rb
    
    it 'validates that emails are unique within a business' do
      business = create(:business)
      create(:user, email: 'test@example.com', business: business)
      
      # Try to create another user with the same email in the same business
      user2 = build(:user, email: 'test@example.com', business: business)
      expect(user2).not_to be_valid
      expect(user2.errors[:email]).to include('has already been taken')
    end
  end
end