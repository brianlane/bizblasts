# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Security Tests', type: :request do
  describe 'Authentication required for protected paths' do
    let(:protected_paths) { %w[/dashboard /manage /settings /profile /account] }

    context 'when not authenticated' do
      %w[GET POST PUT PATCH DELETE].each do |method|
        it "requires authentication for #{method} requests to protected paths" do
          protected_paths.each do |path|
            send(method.downcase, path)
            expect(response).to redirect_to(new_user_session_path),
              "#{method} #{path} should require authentication but got status #{response.status}"
          end
        end
      end
    end

    context 'preventing authentication bypass regression' do
      it 'ensures requires_authentication? returns true for POST requests to protected paths' do
        # Create a dummy controller to test the application controller method
        controller = ApplicationController.new
        allow(controller).to receive(:request).and_return(
          double('request',
            get?: false,
            head?: false,
            post?: true,
            path: '/dashboard'
          )
        )

        expect(controller.send(:requires_authentication?)).to be_truthy,
          "requires_authentication? should return true for POST requests to protected paths"
      end

      it 'ensures requires_authentication? returns true for PUT requests to protected paths' do
        controller = ApplicationController.new
        allow(controller).to receive(:request).and_return(
          double('request',
            get?: false,
            head?: false,
            put?: true,
            path: '/settings'
          )
        )

        expect(controller.send(:requires_authentication?)).to be_truthy,
          "requires_authentication? should return true for PUT requests to protected paths"
      end
    end
  end

  describe 'Tenant logic circular dependency prevention' do
    it 'ensures set_current_tenant does not depend on itself' do
      # Test that TransactionsController can set tenant without circular dependency
      controller = TransactionsController.new

      # Mock request to simulate business domain
      allow(controller).to receive(:request).and_return(
        double('request', host: 'testbiz.example.com', subdomain: 'testbiz')
      )

      # Mock the helper methods
      allow(controller).to receive(:before_action_business_domain_check).and_return(true)

      # This should not cause a circular dependency
      expect {
        controller.send(:set_current_tenant)
      }.not_to raise_error(SystemStackError)
    end
  end
end