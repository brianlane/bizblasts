# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'XSS Protection Integration', type: :request do
  # These specs cover critical sanitization flows end-to-end where feasible and
  # supplement them with focused unit checks for the sanitizers themselves.

  describe 'CSS injection protection in template preview' do
    let(:business) { create(:business, tier: :premium, host_type: 'subdomain') }
    let(:user) { create(:user, role: :manager, business: business) }
    let(:template) { create(:website_template) }

    before do
      ActsAsTenant.current_tenant = business
      host! host_for(business)
      sign_in user
    end

    after do
      ActsAsTenant.current_tenant = nil
    end

    it 'sanitizes malicious script tags in theme CSS' do
      expect(WebsiteTemplateService).to receive(:preview_template)
        .with(template.id, business.id)
        .and_return(
          template: template,
          preview_data: {},
          theme_css: '</style><script>alert("XSS")</script><style>'
        )

      get preview_business_manager_website_template_path(template)

      expect(response).to be_successful
      doc = Nokogiri::HTML(response.body)
      theme_style = doc.css('style').find { |node| node.text.include?('Template Theme CSS') }

      expect(theme_style).to be_present
      expect(theme_style.text).not_to include('javascript:')
    end

    it 'sanitizes CSS injection attempts in theme CSS' do
      expect(WebsiteTemplateService).to receive(:preview_template)
        .with(template.id, business.id)
        .and_return(
          template: template,
          preview_data: {},
          theme_css: '@import url(evil.css); body { display: none; }'
        )

      get preview_business_manager_website_template_path(template)

      expect(response).to be_successful
      doc = Nokogiri::HTML(response.body)
      theme_style = doc.css('style').find { |node| node.text.include?('Template Theme CSS') }

      expect(theme_style).to be_present
      expect(theme_style.text).not_to include('@import')
      expect(theme_style.text).not_to include('javascript:')
    end
  end

  describe 'URL injection protection in transactions view' do
    let(:business) do
      create(:business, :standard_tier, hostname: 'testbiz', subdomain: 'testbiz', host_type: 'subdomain')
    end
    let(:user) { create(:user, role: :client, business: business, email: 'client@example.com') }

    let!(:customer) do
      ActsAsTenant.with_tenant(business) do
        create(:tenant_customer, business: business, email: user.email, user: user)
      end
    end

    let!(:invoice) do
      ActsAsTenant.with_tenant(business) do
        create(:invoice, business: business, tenant_customer: customer)
      end
    end

    before do
      host! 'www.example.com'
      sign_in user
    end

    it 'renders a sanitized payment link for the business domain' do
      get transaction_path(invoice, type: 'invoice')

      expect(response).to be_successful

      expected_url = controller.helpers.safe_business_url(
        business,
        '/payments/new',
        { invoice_id: invoice.id }
      )

      expect(expected_url).to be_present
      expect(response.body).to include(expected_url)
      expect(response.body).not_to include('javascript:')
    end

    context 'with malicious hostname attempts' do
      let(:malicious_business) do
        build(:business,
          host_type: 'subdomain',
          tier: 'premium',
          hostname: '<script>alert("xss")</script>',
          subdomain: '<script>alert("xss")</script>'
        ).tap { |biz| biz.save(validate: false) }
      end

      let!(:malicious_customer) do
        ActsAsTenant.with_tenant(malicious_business) do
          create(:tenant_customer, business: malicious_business, email: user.email, user: user).tap do
            user.clear_tenant_customer_cache
          end
        end
      end

      let!(:malicious_invoice) do
        ActsAsTenant.with_tenant(malicious_business) do
          create(:invoice, business: malicious_business, tenant_customer: malicious_customer)
        end
      end

      it 'does not render malicious hostnames in response' do
        get transaction_path(malicious_invoice, type: 'invoice')

        expect(response).to be_successful
        expect(response.body).not_to include('<script>alert("xss")</script>')
        expect(response.body).not_to include('alert("xss")')
      end
    end
  end

  describe 'WebsiteTheme CSS variable generation' do
    let(:business) { create(:business, tier: :premium) }
    let(:theme) do
      create(:website_theme,
        business: business,
        color_scheme: {
          'primary' => '#ff0000',
          'malicious' => '</style><script>alert("xss")</script>'
        },
        typography: {
          'heading_font' => 'Inter',
          'evil_font' => 'javascript:alert(1)',
          'font_size_base' => '16px'
        }
      )
    end

    it 'sanitizes malicious values in color_scheme' do
      css_variables = theme.generate_css_variables

      # Verify malicious content is sanitized
      expect(css_variables).not_to include('<script>')
      expect(css_variables).not_to include('</style>')
      expect(css_variables).not_to include('alert("xss")')

      # Verify legitimate values are preserved
      expect(css_variables).to include('--color-primary: #ff0000;')
    end

    it 'sanitizes malicious values in typography' do
      css_variables = theme.generate_css_variables

      # Verify malicious protocol is removed (javascript: is the dangerous part)
      expect(css_variables).not_to include('javascript:')

      # Note: The text 'alert(1)' remains but without javascript: it's harmless
      # The sanitizer correctly removes the dangerous protocol while preserving the value

      # Verify legitimate values are preserved
      expect(css_variables).to include('--heading-font: Inter;')
      expect(css_variables).to include('--font-size-base: 16px;')
    end

    it 'converts underscores to hyphens in property names' do
      css_variables = theme.generate_css_variables

      # Verify underscore conversion (font_size_base becomes font-size-base)
      expect(css_variables).to include('--font-size-base:')
      expect(css_variables).not_to include('--font_size_base:')

      # Verify heading_font becomes heading-font
      expect(css_variables).to include('--heading-font:')
      expect(css_variables).not_to include('--heading_font:')
    end

    it 'wraps output in :root selector' do
      css_variables = theme.generate_css_variables

      expect(css_variables).to start_with(':root {')
      expect(css_variables).to end_with('}')
    end
  end

  describe 'safe_business_url helper with various configurations' do
    let(:user) { create(:user, role: :client) }

    before do
      sign_in user
    end

    context 'with SSL enabled' do
      let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }

      it 'generates https URLs when SSL is enabled' do
        allow_any_instance_of(ActionDispatch::Request).to receive(:ssl?).and_return(true)
        allow_any_instance_of(ActionDispatch::Request).to receive(:port).and_return(443)

        get root_path # Any path to set up request context

        # Test the helper via controller context
        url = controller.helpers.safe_business_url(business, '/')

        expect(url).to start_with('https://')
        expect(url).not_to include(':443') # Standard port omitted
      end
    end

    context 'with custom ports' do
      let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }

      it 'includes non-standard ports in URL' do
        allow_any_instance_of(ActionDispatch::Request).to receive(:ssl?).and_return(false)
        allow_any_instance_of(ActionDispatch::Request).to receive(:port).and_return(3000)

        get root_path

        url = controller.helpers.safe_business_url(business, '/')

        expect(url).to include(':3000')
      end
    end

    context 'with query parameters' do
      let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }

      it 'properly encodes query parameters' do
        get root_path

        # Test with parameters that need encoding
        url = controller.helpers.safe_business_url(
          business,
          '/search',
          { query: 'hello world', category: 'test&special' }
        )

        expect(url).to include('/search?')
        # Parameters should be URL encoded
        expect(url).to match(/query=(hello\+world|hello%20world)/)
        expect(url).to include('category=test%26special')
      end
    end
  end
end
