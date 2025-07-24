# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business::RegistrationsController, type: :controller do
  before do
    # Configure devise for controller tests
    @request.env["devise.mapping"] = Devise.mappings[:user]
    # Configure mailer URL options for CI/test environment
    ActionMailer::Base.default_url_options = { host: 'example.com', port: 3000 }
  end
  
  after do
    # Reset mailer URL options
    ActionMailer::Base.default_url_options = {}
  end

  describe '#create' do
    let(:valid_attributes) do
      {
        first_name: 'Test',
        last_name: 'User',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        business_attributes: {
          name: 'Test Business',
          industry: :other,
          phone: '555-123-4567',
          email: 'business@example.com',
          website: 'http://example.com',
          address: '123 Main St',
          city: 'Anytown',
          state: 'CA',
          zip: '12345',
          description: 'A test business',
          tier: 'free',
          hostname: "testbusiness-#{SecureRandom.hex(4)}"
        }
      }
    end

    before do
      allow(Rails.env).to receive(:test?).and_return(true)
    end

    context 'with valid params' do
      it 'creates a new User with manager role' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(User, :count).by(1)
        
        expect(User.last.role).to eq('manager')
      end

      it 'creates a new Business' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(Business, :count).by(1)
        
        business = Business.last
        expect(business.name).to eq('Test Business')
        expect(business.hostname).to be_present
      end

      it 'creates a Staff Member for the business owner' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(StaffMember, :count).by(1)
        
        staff = StaffMember.last
        expect(staff.name).to eq('Test User')
        expect(staff.user).to eq(User.last)
        expect(staff.business).to eq(Business.last)
      end
      
      it 'creates a default Location for the business' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(Location, :count).by(1)
        
        location = Location.last
        business = Business.last
        expect(location.business).to eq(business)
        expect(location.name).to eq('Main Location')
        expect(location.address).to eq(business.address)
        expect(location.city).to eq(business.city)
        expect(location.state).to eq(business.state)
        expect(location.zip).to eq(business.zip)
        expect(location.hours).to be_present
      end

      it 'does not sign in the user immediately (requires email confirmation)' do
        post :create, params: { user: valid_attributes }
        expect(subject.current_user).to be_nil
      end

      # More tests for the happy path
    end

    context 'with platform referral code' do
      let(:test_referral_code) { 'TEST-REFERRAL-123' }
      
      let(:valid_attributes_with_referral) do
        valid_attributes.deep_dup.tap do |attrs|
          attrs[:business_attributes][:platform_referral_code] = test_referral_code
          attrs[:business_attributes][:hostname] = "testbiz-#{SecureRandom.hex(4)}"
        end
      end

      it 'processes platform referral during business registration' do
        expect(PlatformLoyaltyService).to receive(:process_business_referral_signup)
          .with(kind_of(Business), test_referral_code)
          .and_return({ success: true, points_awarded: 500, message: 'Success' })

        post :create, params: { user: valid_attributes_with_referral }

        expect(response).to redirect_to(root_path)
        expect(User.count).to eq(1)
        expect(Business.count).to eq(1)
      end

      it 'handles platform referral processing errors gracefully' do
        expect(PlatformLoyaltyService).to receive(:process_business_referral_signup)
          .with(kind_of(Business), test_referral_code)
          .and_return({ success: false, error: 'Invalid referral code' })

        post :create, params: { user: valid_attributes_with_referral }

        expect(response).to redirect_to(root_path)
        expect(User.count).to eq(1)
        expect(Business.count).to eq(1)
        # Business should still be created even if referral processing fails
      end

      it 'skips platform referral processing when no code provided' do
        expect(PlatformLoyaltyService).not_to receive(:process_business_referral_signup)

        post :create, params: { user: valid_attributes }

        expect(response).to redirect_to(root_path)
        expect(User.count).to eq(1)
        expect(Business.count).to eq(1)
      end

      it 'handles exceptions during platform referral processing' do
        expect(PlatformLoyaltyService).to receive(:process_business_referral_signup)
          .with(kind_of(Business), test_referral_code)
          .and_raise(StandardError.new('Service error'))

        expect(Rails.logger).to receive(:error)
          .with(match(/Error processing platform referral signup/))

        post :create, params: { user: valid_attributes_with_referral }

        expect(response).to redirect_to(root_path)
        expect(User.count).to eq(1)
        expect(Business.count).to eq(1)
      end

      it 'treats blank platform referral code as nil to avoid uniqueness errors' do
        # First request with blank code
        attrs1 = valid_attributes.deep_dup
        attrs1[:business_attributes][:platform_referral_code] = ''
        attrs1[:business_attributes][:hostname] = "biz1-#{SecureRandom.hex(4)}"

        expect {
          post :create, params: { user: attrs1 }
        }.to change(Business, :count).by(1)

        # Second request also with blank code should succeed
        attrs2 = valid_attributes.deep_dup
        attrs2[:email] = "user2-#{SecureRandom.hex(4)}@example.com"
        attrs2[:business_attributes][:platform_referral_code] = ''
        attrs2[:business_attributes][:hostname] = "biz2-#{SecureRandom.hex(4)}"

        expect {
          post :create, params: { user: attrs2 }
        }.to change(Business, :count).by(1)
      end

      it 'does not create resources and re-renders the form with flash alert when an unrecognised industry is supplied' do
        unrecognised_industry = 'Chef Jenn LLC'
        attributes_with_bad_industry = valid_attributes.deep_dup
        attributes_with_bad_industry[:business_attributes][:industry] = unrecognised_industry

        expect {
          post :create, params: { user: attributes_with_bad_industry }
        }.not_to change(Business, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
        expect(flash[:alert]).to match(/not a recognised industry/i)
      end
    end

    context 'with invalid params' do
      # Add tests for error scenarios
    end
  end
end 