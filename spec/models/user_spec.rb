# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business).optional }
    it { is_expected.to belong_to(:staff_member).optional }
    it { is_expected.to have_many(:client_businesses).dependent(:destroy) }
    it { is_expected.to have_many(:businesses).through(:client_businesses) }
    it { is_expected.to have_many(:staff_assignments).dependent(:destroy) }
    it { is_expected.to have_many(:assigned_services).through(:staff_assignments).source(:service) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:role) }

    context 'with email uniqueness scoped by role type' do
      let!(:existing_client) { create(:user, role: :client, email: 'test@example.com') }
      let!(:business1) { create(:business) }
      let!(:existing_manager) { create(:user, role: :manager, email: 'manager@example.com', business: business1) }
      let!(:business2) { create(:business) }

      it 'disallows a manager and client to have the same email' do
        new_manager = build(:user, role: :manager, email: existing_client.email, business: business2)
        expect(new_manager).not_to be_valid
        expect(new_manager.errors[:email]).to include("has already been taken")
      end

      it 'disallows duplicate emails for clients' do
        duplicate_client = build(:user, role: :client, email: 'test@example.com')
        expect(duplicate_client).not_to be_valid
        expect(duplicate_client.errors[:email]).to include('has already been taken')
      end

      it 'disallows duplicate emails for business users (manager/staff)' do
        duplicate_manager = build(:user, role: :manager, email: 'manager@example.com', business: business2)
        expect(duplicate_manager).not_to be_valid
        expect(duplicate_manager.errors[:email]).to include('has already been taken')

        new_staff = build(:user, role: :staff, email: 'manager@example.com', business: business2)
        expect(new_staff).not_to be_valid
        expect(new_staff.errors[:email]).to include('has already been taken')
      end

      it 'allows updating a user without changing email' do
        existing_client.first_name = "Updated"
        expect(existing_client).to be_valid
        
        existing_manager.first_name = "Updated Manager"
        expect(existing_manager).to be_valid
      end

      it 'is invalid if email is taken by a user with any role' do
        new_client = build(:user, role: :client, email: existing_manager.email)
        expect(new_client).not_to be_valid
        expect(new_client.errors[:email]).to include("has already been taken")

        new_manager = build(:user, role: :manager, email: existing_client.email, business: business2)
        expect(new_manager).not_to be_valid
        expect(new_manager.errors[:email]).to include("has already been taken")
      end
    end

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

  describe 'policy acceptance methods' do
    let(:user) { create(:user, role: :client) }
    let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
    let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true) }
    let!(:aup_policy) { create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true) }
    let!(:return_policy) { create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true) }
    
    describe '#needs_policy_acceptance?' do
      context 'when requires_policy_acceptance is true' do
        before { user.update!(requires_policy_acceptance: true) }
        
        it 'returns true' do
          expect(user.needs_policy_acceptance?).to be true
        end
      end
      
      context 'when user has missing required policies' do
        it 'returns true for client with missing policies' do
          client = create(:user, role: :client)
          expect(client.needs_policy_acceptance?).to be true
        end
        
        it 'returns true for manager with missing policies' do
          manager = create(:user, :manager)
          expect(manager.needs_policy_acceptance?).to be true
        end
      end
      
      context 'when user has accepted all required policies' do
        let(:client) { create(:user, role: :client) }
        
        before do
          create(:policy_acceptance, user: client, policy_type: 'privacy_policy', policy_version: 'v1.0')
          create(:policy_acceptance, user: client, policy_type: 'terms_of_service', policy_version: 'v1.0')
          create(:policy_acceptance, user: client, policy_type: 'acceptable_use_policy', policy_version: 'v1.0')
        end
        
        it 'returns false' do
          expect(client.needs_policy_acceptance?).to be false
        end
      end
    end
    
    describe '#missing_required_policies' do
      context 'for client users' do
        let(:client) { create(:user, role: :client) }
        
        it 'returns all required policies when none are accepted' do
          missing = client.missing_required_policies
          expect(missing).to include('privacy_policy', 'terms_of_service', 'acceptable_use_policy')
          expect(missing).not_to include('return_policy')
        end
        
        it 'returns only unaccepted policies' do
          create(:policy_acceptance, user: client, policy_type: 'privacy_policy', policy_version: 'v1.0')
          
          missing = client.missing_required_policies
          expect(missing).to include('terms_of_service', 'acceptable_use_policy')
          expect(missing).not_to include('privacy_policy')
        end
        
        it 'returns empty array when all policies are accepted' do
          create(:policy_acceptance, user: client, policy_type: 'privacy_policy', policy_version: 'v1.0')
          create(:policy_acceptance, user: client, policy_type: 'terms_of_service', policy_version: 'v1.0')
          create(:policy_acceptance, user: client, policy_type: 'acceptable_use_policy', policy_version: 'v1.0')
          
          expect(client.missing_required_policies).to be_empty
        end
      end
      
      context 'for business users' do
        let(:manager) { create(:user, :manager) }
        
        it 'includes return policy for managers' do
          missing = manager.missing_required_policies
          expect(missing).to include('privacy_policy', 'terms_of_service', 'acceptable_use_policy', 'return_policy')
        end
        
        it 'includes return policy for staff' do
          staff = create(:user, :staff)
          missing = staff.missing_required_policies
          expect(missing).to include('privacy_policy', 'terms_of_service', 'acceptable_use_policy', 'return_policy')
        end
      end
      
      context 'when policy version does not exist' do
        before do
          privacy_policy.destroy
        end
        
        it 'skips policies without current versions' do
          client = create(:user, role: :client)
          missing = client.missing_required_policies
          expect(missing).not_to include('privacy_policy')
          expect(missing).to include('terms_of_service', 'acceptable_use_policy')
        end
      end
      
      context 'when user accepted old version' do
        let(:client) { create(:user, role: :client) }
        
        before do
          # User accepted old version
          create(:policy_acceptance, user: client, policy_type: 'privacy_policy', policy_version: 'v0.9')
          # New version is active
          privacy_policy.update!(version: 'v1.0')
        end
        
        it 'includes policy with outdated acceptance' do
          missing = client.missing_required_policies
          expect(missing).to include('privacy_policy')
        end
      end
    end
    
    describe '#mark_policies_accepted!' do
      before do
        user.update!(requires_policy_acceptance: true, last_policy_notification_at: nil)
      end
      
      it 'sets requires_policy_acceptance to false' do
        expect {
          user.mark_policies_accepted!
        }.to change { user.requires_policy_acceptance }.from(true).to(false)
      end
      
      it 'sets last_policy_notification_at to current time' do
        time_before = Time.current
        user.mark_policies_accepted!
        time_after = Time.current
        
        expect(user.last_policy_notification_at).to be_between(time_before, time_after)
      end
    end
  end

  describe 'unsubscribe token generation' do
    let(:business) { create(:business) }
    
    it 'generates a unique unsubscribe token' do
      user = create(:user, role: :client)
      expect(user.unsubscribe_token).to be_present
      expect(user.unsubscribe_token.length).to eq(64) # 32 hex chars = 64 characters
    end
    
    it 'ensures tokens are unique across User and TenantCustomer tables' do
      # Create a user with a specific token
      user = create(:user, role: :client)
      original_token = user.unsubscribe_token
      
      # Create a tenant customer and force it to try to use the same token
      tenant_customer = build(:tenant_customer, business: business)
      tenant_customer.unsubscribe_token = original_token
      
      # The generate_unsubscribe_token method should detect the collision and generate a new token
      tenant_customer.send(:generate_unsubscribe_token)
      
      expect(tenant_customer.unsubscribe_token).not_to eq(original_token)
      expect(tenant_customer.unsubscribe_token).to be_present
    end
    
    it 'regenerates a new unique token' do
      user = create(:user, role: :client)
      original_token = user.unsubscribe_token
      
      user.send(:regenerate_unsubscribe_token)
      
      expect(user.unsubscribe_token).not_to eq(original_token)
      expect(user.unsubscribe_token).to be_present
    end
  end

  describe 'default notification preferences' do
    it 'sets default notification preferences for new users' do
      user = create(:user, role: :client)
      
      expect(user.notification_preferences).to be_present
      expect(user.notification_preferences['email_booking_confirmation']).to eq(true)
      expect(user.notification_preferences['sms_booking_reminder']).to eq(true)
      expect(user.notification_preferences['email_booking_updates']).to eq(true)
      expect(user.notification_preferences['email_order_updates']).to eq(true)
      expect(user.notification_preferences['sms_order_updates']).to eq(true)
      expect(user.notification_preferences['email_payment_confirmations']).to eq(true)
      expect(user.notification_preferences['email_promotions']).to eq(true)
      expect(user.notification_preferences['email_blog_updates']).to eq(true)
      expect(user.notification_preferences['sms_promotions']).to eq(true)
      expect(user.notification_preferences['email_booking_notifications']).to eq(true)
      expect(user.notification_preferences['email_marketing_notifications']).to eq(true)
    end

    it 'does not override existing notification preferences' do
      existing_prefs = { 'email_booking_confirmation' => false, 'sms_booking_reminder' => true }
      user = create(:user, role: :client, notification_preferences: existing_prefs)
      
      expect(user.notification_preferences).to eq(existing_prefs)
      expect(user.notification_preferences['email_booking_confirmation']).to eq(false)
    end

    it 'sets defaults for all user roles' do
      [:client, :manager, :staff].each do |role|
        business = role.in?([:manager, :staff]) ? create(:business) : nil
        user = create(:user, role: role, business: business)
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(true)
      end
    end
    
    context 'with notification consent during registration' do
      it 'enables all notifications when consent is given (default)' do
        user = build(:user, role: :client)
        user.bizblasts_notification_consent = '1'
        user.save!
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(true)
        expect(user.notification_preferences['email_promotions']).to eq(true)
        expect(user.notification_preferences['email_marketing_notifications']).to eq(true)
        expect(user.notification_preferences['sms_booking_reminder']).to eq(true)
      end
      
      it 'disables all notifications when consent is not given' do
        user = build(:user, role: :client)
        user.bizblasts_notification_consent = '0'
        user.save!
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(false)
        expect(user.notification_preferences['email_promotions']).to eq(false)
        expect(user.notification_preferences['email_marketing_notifications']).to eq(false)
        expect(user.notification_preferences['sms_booking_reminder']).to eq(false)
        expect(user.notification_preferences['sms_promotions']).to eq(false)
      end
      
      it 'enables notifications when consent is explicitly true' do
        user = build(:user, role: :client)
        user.bizblasts_notification_consent = true
        user.save!
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(true)
        expect(user.notification_preferences['email_promotions']).to eq(true)
        expect(user.notification_preferences['sms_booking_reminder']).to eq(true)
      end
      
      it 'disables notifications when consent is explicitly false' do
        user = build(:user, role: :client)
        user.bizblasts_notification_consent = false
        user.save!
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(false)
        expect(user.notification_preferences['email_promotions']).to eq(false)
        expect(user.notification_preferences['sms_booking_reminder']).to eq(false)
      end
      
      it 'works for business users too' do
        business = create(:business)
        user = build(:user, role: :manager, business: business)
        user.bizblasts_notification_consent = '0'
        user.save!
        
        expect(user.notification_preferences).to be_present
        expect(user.notification_preferences['email_booking_confirmation']).to eq(false)
        expect(user.notification_preferences['email_system_notifications']).to eq(false)
        expect(user.notification_preferences['sms_booking_reminder']).to eq(false)
      end
    end
  end
end