# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "CSRF Protection Configuration", type: :request do
  describe "Security documentation for CSRF protection changes" do
    it "Admin::SessionsController has rescue_from for CSRF errors" do
      controller_file = File.read(Rails.root.join('app/controllers/admin/sessions_controller.rb'))

      expect(controller_file).to include('rescue_from ActionController::InvalidAuthenticityToken')
      expect(controller_file).to include('handle_invalid_token')
      expect(controller_file).to include('reset_csrf_token')
    end

    it "Stripe webhook controller has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/stripe_webhooks_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('skip_before_action :verify_authenticity_token')
      expect(controller_file).to include('CWE-352')
    end

    it "Calendar OAuth controller has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/calendar_oauth_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('OAuth')
      expect(controller_file).to include('state parameter')
    end

    it "API controller has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/api/v1/businesses_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('API key authentication')
      expect(controller_file).to include('CWE-352')
    end

    it "Health controller has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/health_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('monitoring endpoints')
      expect(controller_file).to include('CWE-352')
    end

    it "Maintenance controller has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/maintenance_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('maintenance/error pages')
      expect(controller_file).to include('CWE-352')
    end

    it "Public::SubdomainsController has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/public/subdomains_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('null_session')
      expect(controller_file).to include('CWE-352')
    end

    it "Users::SessionsController has security documentation for JSON API" do
      controller_file = File.read(Rails.root.join('app/controllers/users/sessions_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('JSON API')
      expect(controller_file).to include('CWE-352')
    end

    it "BusinessManager::Settings::SubscriptionsController has security documentation" do
      controller_file = File.read(Rails.root.join('app/controllers/business_manager/settings/subscriptions_controller.rb'))

      expect(controller_file).to include('SECURITY:')
      expect(controller_file).to include('webhook')
      expect(controller_file).to include('Stripe signature')
    end
  end

  describe "Removed unnecessary CSRF skips" do
    it "Admin dashboard no longer skips CSRF" do
      dashboard_file = File.read(Rails.root.join('app/admin/dashboard.rb'))

      # Should NOT have skip_before_action :verify_authenticity_token for index
      lines_with_skip = dashboard_file.lines.grep(/skip_before_action.*verify_authenticity_token.*only.*index/)

      expect(lines_with_skip).to be_empty,
        "Admin dashboard should not skip CSRF for index action"
    end

    it "ReviewRequestUnsubscribesController documentation updated" do
      controller_file = File.read(Rails.root.join('app/controllers/review_request_unsubscribes_controller.rb'))

      # Should have note explaining why no CSRF skip needed
      expect(controller_file).to include('CSRF Note:')
        .or include('GET-only')
        .or include('signed token')
    end

    it "TenantRedirectController documentation updated" do
      controller_file = File.read(Rails.root.join('app/controllers/tenant_redirect_controller.rb'))

      # Should have note explaining GET-only nature
      expect(controller_file).to include('CSRF Note:')
        .or include('GET redirects')
        .or include('GET-only')
    end
  end

  describe "Public::OrdersController null_session pattern" do
    it "uses null_session for promo code validation" do
      controller_file = File.read(Rails.root.join('app/controllers/public/orders_controller.rb'))

      expect(controller_file).to include('null_session')
      expect(controller_file).to include('validate_promo_code')
    end
  end

  describe "All CSRF skips are documented" do
    it "has comprehensive security documentation explaining each skip" do
      controllers_with_csrf_skips = [
        'app/controllers/stripe_webhooks_controller.rb',
        'app/controllers/business_manager/settings/subscriptions_controller.rb',
        'app/controllers/calendar_oauth_controller.rb',
        'app/controllers/api/v1/businesses_controller.rb',
        'app/controllers/health_controller.rb',
        'app/controllers/maintenance_controller.rb',
        'app/controllers/public/subdomains_controller.rb',
        'app/controllers/users/sessions_controller.rb',
        'app/controllers/public/orders_controller.rb'
      ]

      controllers_with_csrf_skips.each do |controller_path|
        full_path = Rails.root.join(controller_path)
        expect(File.exist?(full_path)).to be_truthy

        controller_file = File.read(full_path)

        # Should have security documentation
        expect(controller_file).to include('SECURITY:'),
          "#{controller_path} should have SECURITY: documentation"

        # Should mention CWE-352 or explain why skip is legitimate
        has_documentation = controller_file.include?('CWE-352') ||
                           controller_file.include?('legitimate') ||
                           controller_file.include?('LEGITIMATE')

        expect(has_documentation).to be_truthy,
          "#{controller_path} should explain why CSRF skip is legitimate (CWE-352 or 'legitimate')"
      end
    end
  end
end
