# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business).optional }
    it { is_expected.to belong_to(:staff_member).optional }
    it { is_expected.to have_many(:client_businesses).dependent(:destroy) }
    it { is_expected.to have_many(:associated_businesses).through(:client_businesses).source(:business) }
  end

  describe 'validations' do
    it 'validates uniqueness of email globally' do
      create(:user, email: 'unique@example.com')
      duplicate = build(:user, email: 'unique@example.com')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end
    
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:role) }

    context 'when role requires a business (manager/staff)' do
      let(:business) { create(:business) }
      
      it 'is valid with a business' do
        user = build(:user, role: :manager, business: business)
        expect(user).to be_valid
        user = build(:user, role: :staff, business: business)
        expect(user).to be_valid
      end

      it 'is invalid without a business' do
        user = build(:user, role: :manager, business: nil)
        expect(user).not_to be_valid
        expect(user.errors[:business_id]).to include("can't be blank")
        user = build(:user, role: :staff, business: nil)
        expect(user).not_to be_valid
        expect(user.errors[:business_id]).to include("can't be blank")
      end
    end

    context 'when role does not require a business (client)' do
      it 'is valid without a business' do
        user = build(:user, role: :client, business: nil)
        expect(user).to be_valid
      end
      
      it 'is valid with a business (though business_id will be ignored/nulled later for clients)' do
        business = create(:business)
        user = build(:user, role: :client, business: business) 
        expect(user).to be_valid 
      end
    end
  end

  describe 'scopes' do
    let!(:business) { create(:business) }
    let!(:active_user) { create(:user, active: true, role: :client) }
    let!(:inactive_user) { create(:user, active: false, role: :client) }
    let!(:manager) { create(:user, role: :manager, business: business) }
    let!(:staff) { create(:user, role: :staff, business: business) }
    let!(:client) { create(:user, role: :client) }

    it '.active returns only active users' do
      expect(User.active.to_a).to include(active_user)
      expect(User.active.to_a).not_to include(inactive_user)
    end

    it '.business_users returns manager and staff roles' do
      expect(User.business_users.to_a).to include(manager, staff)
      expect(User.business_users.to_a).not_to include(client, active_user, inactive_user)
    end
    
    it '.clients returns only client roles' do
       expect(User.clients.to_a).to include(client, active_user, inactive_user)
       expect(User.clients.to_a).not_to include(manager, staff)
    end
  end

  describe 'role enum' do
    it 'defines roles (excluding admin)' do
      expect(User.roles.keys).to contain_exactly('manager', 'staff', 'client')
    end
    
    it 'defaults role to client' do
      user = User.new
      expect(user.role).to eq('client')
    end
  end

  describe '#requires_business?' do
    it 'returns true for manager roles' do
      user = build(:user, role: :manager)
      expect(user.requires_business?).to be true
    end

    it 'returns true for staff roles' do
      user = build(:user, role: :staff)
      expect(user.requires_business?).to be true
    end

    it 'returns false for client roles' do
      user = build(:user, role: :client)
      expect(user.requires_business?).to be false
    end
  end

  describe '#full_name' do
    context 'when first and last name are present' do
      it 'returns the combined first and last name' do
        user = build(:user, first_name: 'John', last_name: 'Doe', email: 'test@example.com')
        expect(user.full_name).to eq('John Doe')
      end
    end
    
    context 'when only first name is present' do
      it 'returns the first name' do
        user = build(:user, first_name: 'John', last_name: nil, email: 'test@example.com')
        expect(user.full_name).to eq('John')
      end
    end

    context 'when only last name is present' do
      it 'returns the last name' do
        user = build(:user, first_name: nil, last_name: 'Doe', email: 'test@example.com')
        expect(user.full_name).to eq('Doe')
      end
    end

    context 'when first and last name are blank' do
      it 'returns the email' do
        user = build(:user, first_name: nil, last_name: '', email: 'test@example.com')
        expect(user.full_name).to eq('test@example.com')
      end
    end
  end
end