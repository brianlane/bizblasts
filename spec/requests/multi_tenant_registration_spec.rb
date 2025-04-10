# frozen_string_literal: true

require 'rails_helper'

# NOTE: This spec tested the ability to have duplicate emails scoped to different tenants.
# With the user model refactoring (global email uniqueness), this is no longer valid.
# Keeping the file but commenting out the tests.
RSpec.describe "MultiTenant Registration", type: :request do
  # let(:email) { "same_user@example.com" }
  # let(:password) { "password123" }
  # let(:business1) { create(:business, name: "First Business", subdomain: "first") }
  # let(:business2) { create(:business, name: "Second Business", subdomain: "second") }

  # Helper to set the host with subdomain
  # def set_host(subdomain)
  #   host! "#{subdomain}.example.com"
  # end

  # Reset session between requests
  # def reset_session_and_tenant
  #   @request.reset_session if @request
  #   ActsAsTenant.current_tenant = nil
  # end

  # describe "users with identical emails in different tenants" do
  #   it "allows registration and authentication with the same email in different businesses" do
      # Test is no longer valid due to global email uniqueness
  #   end
  # end
end 