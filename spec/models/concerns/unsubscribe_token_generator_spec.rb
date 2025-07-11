# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnsubscribeTokenGenerator do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include ActiveModel::Model
      include UnsubscribeTokenGenerator
      
      attr_accessor :id, :unsubscribe_token
      
      def persisted?
        id.present?
      end
      
      def save(validate: true)
        # Mock save method
        true
      end
    end
  end
  
  let(:test_instance) { test_class.new }
  
  describe '#generate_unsubscribe_token' do
    let(:business) { create(:business) }
    
    it 'generates a unique token when no conflicts exist' do
      test_instance.send(:generate_unsubscribe_token)
      
      expect(test_instance.unsubscribe_token).to be_present
      expect(test_instance.unsubscribe_token.length).to eq(64)
    end
    
    it 'avoids conflicts with existing User tokens' do
      # Create a user with a specific token
      user = create(:user, role: :client)
      existing_token = user.unsubscribe_token
      
      # Try to generate a token for our test instance
      test_instance.send(:generate_unsubscribe_token)
      
      # The generated token should be different
      expect(test_instance.unsubscribe_token).not_to eq(existing_token)
    end
    
    it 'avoids conflicts with existing TenantCustomer tokens' do
      ActsAsTenant.with_tenant(business) do
        # Create a tenant customer with a specific token
        customer = create(:tenant_customer, business: business)
        existing_token = customer.unsubscribe_token
        
        # Try to generate a token for our test instance
        test_instance.send(:generate_unsubscribe_token)
        
        # The generated token should be different
        expect(test_instance.unsubscribe_token).not_to eq(existing_token)
      end
    end
    
    it 'handles conflicts by generating a new token' do
      # Create both a user and tenant customer with the same token
      user = create(:user, role: :client)
      user_token = user.unsubscribe_token
      
      ActsAsTenant.with_tenant(business) do
        customer = create(:tenant_customer, business: business)
        # Force the customer to have the same token as the user
        customer.update_column(:unsubscribe_token, user_token)
        
        # Now try to generate a token for our test instance
        test_instance.send(:generate_unsubscribe_token)
        
        # The generated token should be different from both
        expect(test_instance.unsubscribe_token).not_to eq(user_token)
        expect(test_instance.unsubscribe_token).to be_present
      end
    end
  end
  
  describe '#regenerate_unsubscribe_token' do
    it 'calls generate_unsubscribe_token' do
      expect(test_instance).to receive(:generate_unsubscribe_token)
      test_instance.send(:regenerate_unsubscribe_token)
    end
  end
end 