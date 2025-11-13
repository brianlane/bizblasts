require 'rails_helper'

RSpec.describe TenantCustomer, type: :model do
  let(:business) { create(:business) }
  
  describe 'validations' do
    subject { build(:tenant_customer, business: business) }

    # first_name and last_name are now optional to support newsletter signups
    it { should validate_length_of(:first_name).is_at_most(255) }
    it { should validate_length_of(:last_name).is_at_most(255) }
    it { should validate_presence_of(:email) }
    
    describe 'email uniqueness per business' do
      let!(:existing_customer) { create(:tenant_customer, business: business, email: 'test@example.com') }
      
      it 'prevents duplicate emails in same business' do
        duplicate = build(:tenant_customer, business: business, email: 'test@example.com')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:email]).to include('must be unique within this business')
      end
      
      it 'allows same email in different businesses' do
        other_business = create(:business)
        other_customer = build(:tenant_customer, business: other_business, email: 'test@example.com')
        expect(other_customer).to be_valid
      end
      
      it 'handles case-insensitive uniqueness' do
        duplicate = build(:tenant_customer, business: business, email: 'TEST@EXAMPLE.COM')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:email]).to include('must be unique within this business')
      end
    end
  end
  
  describe 'email normalization' do
    it 'normalizes email to lowercase' do
      customer = create(:tenant_customer, business: business, email: 'TEST@EXAMPLE.COM')
      expect(customer.email).to eq('test@example.com')
    end
    
    it 'strips whitespace from email' do
      customer = create(:tenant_customer, business: business, email: '  test@example.com  ')
      expect(customer.email).to eq('test@example.com')
    end
  end
  
  describe 'notification preferences' do
    let(:user) { create(:user, :client) }
    let(:customer) { create(:tenant_customer, business: business, user: user) }
    
    context 'when user has notification preferences' do
      before do
        user.update!(notification_preferences: {
          'booking_confirmations' => true,
          'marketing_emails' => false,
          'appointment_reminders' => true
        })
      end
      
      it 'respects user preferences for enabled notifications' do
        expect(customer.notification_enabled?('booking_confirmations')).to be true
        expect(customer.notification_enabled?('appointment_reminders')).to be true
      end
      
      it 'respects user preferences for disabled notifications' do
        expect(customer.notification_enabled?('marketing_emails')).to be false
      end
      
      it 'defaults to enabled for unspecified preferences' do
        expect(customer.notification_enabled?('new_feature_announcements')).to be true
      end
    end
    
    context 'when user has no preferences' do
      it 'defaults to enabled' do
        expect(customer.notification_enabled?('booking_confirmations')).to be true
      end
    end
    
    context 'when customer has no associated user' do
      let(:guest_customer) { create(:tenant_customer, business: business, user: nil) }
      
      it 'uses customer preferences' do
        expect(guest_customer.notification_enabled?('booking_confirmations')).to be true
      end
    end
  end
  
  describe 'phone validation' do
    it 'allows blank phone numbers' do
      customer = build(:tenant_customer, business: business, phone: '')
      expect(customer).to be_valid
    end
    
    it 'allows nil phone numbers' do
      customer = build(:tenant_customer, business: business, phone: nil)
      expect(customer).to be_valid
    end
    
    it 'allows valid phone numbers' do
      customer = build(:tenant_customer, business: business, phone: '555-123-4567')
      expect(customer).to be_valid
    end
  end
  
  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:user).optional }
    it { should have_many(:bookings).dependent(:destroy) }
    it { should have_many(:invoices).dependent(:destroy) }
    it { should have_many(:orders).dependent(:destroy) }
  end
  
  describe 'database constraints' do
    let!(:customer) { create(:tenant_customer, business: business, email: 'test@example.com') }
    
    it 'enforces unique constraint on business_id + LOWER(email)' do
      expect {
        # This should fail at the database level due to unique index
        TenantCustomer.connection.execute(
          "INSERT INTO tenant_customers (business_id, email, first_name, last_name, created_at, updated_at) 
           VALUES (#{business.id}, 'TEST@EXAMPLE.COM', 'Test', 'User', NOW(), NOW())"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /duplicate key value violates unique constraint/)
    end
  end
end