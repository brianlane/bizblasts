# frozen_string_literal: true

require 'rails_helper'

# Coverage for the BizBlasts platform legal pages now that they are served
# directly from the codebase instead of from termly.io embeds (see PR
# replacing termly with newCoworker-style LegalPage views), and now that the
# same routes are exposed on tenant subdomains and tenant custom domains so
# visitors to URLs like https://www.losnemassageaz.com/terms see the
# BizBlasts Terms of Service rather than a fall-back to the tenant's home
# template.
RSpec.describe 'Platform legal pages', type: :request do
  # Distinctive copy from each rewritten view. Picking a phrase that does not
  # appear in any tenant home template, the layout, or unrelated marketing
  # pages, so a hit confirms the right view rendered.
  LEGAL_PAGES = {
    '/terms'               => 'These Terms of Service govern access',
    '/privacypolicy'       => 'This Privacy Policy explains how BizBlasts',
    '/disclaimer'          => 'BizBlasts and on sites we host',
    '/shippingpolicy'      => 'BizBlasts Is a Software Platform',
    '/returnpolicy'        => 'BizBlasts Subscription Fees',
    '/acceptableusepolicy' => 'Acceptable Use Policy'
  }.freeze

  # /cookies is intentionally kept on the termly.io embed for now (per the
  # request that left the cookie consent solution unchanged), so the marker
  # we look for is the termly embed tag rather than rewritten copy.
  COOKIES_MARKER = 'termly-embed'

  shared_examples 'renders all platform legal pages' do
    LEGAL_PAGES.each do |path, marker|
      it "GET #{path} returns 200 and renders the rewritten content" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(marker)
      end
    end

    it 'GET /cookies still serves the termly cookie-policy embed' do
      get '/cookies'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(COOKIES_MARKER)
    end
  end

  context 'on the main domain (www.example.com in test env)' do
    before { host! 'www.example.com' }
    include_examples 'renders all platform legal pages'
  end

  context 'on a tenant subdomain' do
    let!(:business) do
      slug = "tenant#{SecureRandom.hex(3)}"
      # The :after_build hook on :business mirrors hostname into subdomain
      # automatically for host_type=subdomain.
      create(:business, host_type: 'subdomain', hostname: slug)
    end

    before do
      # AllowedHostService.valid_platform_subdomain? accepts <slug>.example.com
      # in test env; the chars produced by SecureRandom.hex (0-9, a-f) all
      # match the [a-z0-9-] character class used in that regex.
      host! "#{business.hostname}.example.com"
    end

    include_examples 'renders all platform legal pages'

    it 'GET /terms does NOT fall through to the tenant home template' do
      # The pre-fix bug was that the /:page catch-all routed `terms` to
      # Public::PagesController#show, which then rendered public/pages/home
      # because no tenant page with slug `terms` existed. Make sure that the
      # rendered body looks like Terms of Service, not the tenant home page.
      get '/terms'
      expect(response.body).to include('These Terms of Service govern access')
      expect(response.body).not_to include('Our Services')
    end
  end

  context 'on a tenant custom domain' do
    let!(:business) do
      # We need a hostname that is BOTH:
      #   * allowed by Rails' ActionDispatch::HostAuthorization
      #     (config/environments/test.rb permits /[a-z0-9\-]+\.example\.com/), and
      #   * resolvable via CustomDomainConstraint -> find_business_by_custom_domain.
      # The set_tenant logic tries custom-domain lookup BEFORE subdomain lookup,
      # so even though "<slug>.example.com" looks like a subdomain to Rails, the
      # presence of a matching Business row with host_type=custom_domain causes
      # the request to flow through the custom-domain path.
      create(:business,
             host_type: 'custom_domain',
             hostname: "customdomain-#{SecureRandom.hex(3)}.example.com",
             status: 'cname_active',
             domain_health_verified: true)
    end

    before do
      # AllowedHostService caches custom-domain lookups for 5 minutes; clear
      # the cache so the test's freshly-created Business is visible to the
      # request-host check.
      Rails.cache.clear
      host! business.hostname
    end

    include_examples 'renders all platform legal pages'

    it 'GET /terms does NOT fall through to the tenant home template' do
      get '/terms'
      expect(response.body).to include('These Terms of Service govern access')
      expect(response.body).not_to include('Our Services')
    end
  end
end
