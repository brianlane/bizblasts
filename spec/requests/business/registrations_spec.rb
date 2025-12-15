# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business::Registrations", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "POST /business" do
    let(:user_attributes) do
      {
        first_name: "Test",
        last_name: "Manager",
        email: "manager-#{SecureRandom.hex(6)}@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    end

    let(:base_business_attributes) do
      {
        name: "Test Biz",
        industry: 'other',
        phone: "1234567890",
        email: "contact-#{SecureRandom.hex(6)}@testbiz.com",
        address: "123 Main St",
        city: "Anytown",
        state: "CA",
        zip: "12345",
        description: "A test business"
      }
    end

    def post_signup!(business_attributes)
      post business_registration_path, params: {
        user: user_attributes.merge(
          business_attributes: base_business_attributes.merge(business_attributes)
        )
      }
    end

    shared_examples "creates business + manager" do |business_attributes:, expected_host_type:, expected_hostname:|
      it "creates User, Business, and default StaffMember" do
        expect do
          post_signup!(business_attributes)
        end.to change(User, :count).by(1)
          .and change(Business, :count).by(1)
          .and change(StaffMember, :count).by(1)

        new_user = User.last
        new_business = Business.last

        expect(new_user.manager?).to be true
        expect(new_user.business).to eq(new_business)

        expect(new_business.host_type).to eq(expected_host_type)
        expect(new_business.hostname).to eq(expected_hostname)
      end

      it "redirects to root (confirmable flow) and does not sign in immediately" do
        post_signup!(business_attributes)

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(
          "A message with a confirmation link has been sent to your email address. Please follow the link to activate your account."
        )
        expect(controller.current_user).to be_nil
      end
    end

    context "with subdomain" do
      include_examples "creates business + manager",
                       business_attributes: { subdomain: 'test-biz' },
                       expected_host_type: 'subdomain',
                       expected_hostname: 'test-biz'
    end

    context "with custom domain" do
      include_examples "creates business + manager",
                       business_attributes: { hostname: 'premium-biz.com' },
                       expected_host_type: 'custom_domain',
                       expected_hostname: 'premium-biz.com'
    end

    context "with invalid parameters" do
      it "does not create records when user validation fails" do
        bad_user = user_attributes.merge(email: 'invalid')

        expect do
          post business_registration_path, params: {
            user: bad_user.merge(business_attributes: base_business_attributes.merge(subdomain: 'test-biz'))
          }
        end.not_to change { [User.count, Business.count, StaffMember.count] }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create records when business validation fails" do
        expect do
          post_signup!(subdomain: 'test-biz', name: '')
        end.not_to change { [User.count, Business.count, StaffMember.count] }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
