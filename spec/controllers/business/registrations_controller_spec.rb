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
          subdomain: "testbusiness-#{SecureRandom.hex(4)}"
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

    context 'with invalid params' do
      it 'does not create resources and re-renders the form with flash alert when an unrecognised industry is supplied' do
        unrecognised_industry = 'Chef Jenn LLC'
        attributes_with_bad_industry = valid_attributes.deep_dup
        attributes_with_bad_industry[:business_attributes][:industry] = unrecognised_industry

        expect {
          post :create, params: { user: attributes_with_bad_industry }
        }.not_to change(Business, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response).to render_template(:new)
        expect(flash[:alert]).to match(/not a recognised industry/i)
      end
    end
  end
end 