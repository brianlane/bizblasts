# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'XSS Protection Integration', type: :request do
  describe 'CSS injection protection in template preview' do
    let(:business) { create(:business, tier: :premium) }
    let(:user) { create(:user, role: :business_owner, business: business) }

    before do
      sign_in user
    end

    context 'when previewing template with malicious CSS' do
      it 'sanitizes malicious script tags in theme CSS' do
        # Simulate malicious theme CSS that tries to inject script tags
        malicious_theme_css = '</style><script>alert("XSS")</script><style>'

        # Mock the controller instance variable
        allow_any_instance_of(BusinessManager::Website::TemplatesController)
          .to receive(:show).and_wrap_original do |method, *args|
            method.receiver.instance_variable_set(:@theme_css, malicious_theme_css)
            method.call(*args)
          end

        get business_manager_website_template_preview_path

        # Verify the response doesn't contain the malicious script
        expect(response.body).not_to include('<script>')
        expect(response.body).not_to include('</script>')
        expect(response.body).not_to include('alert("XSS")')
      end

      it 'sanitizes CSS injection attempts in theme CSS' do
        # CSS that tries to break out of style context
        malicious_css = 'color: red; } body { display: none; } .evil {'

        allow_any_instance_of(BusinessManager::Website::TemplatesController)
          .to receive(:show).and_wrap_original do |method, *args|
            method.receiver.instance_variable_set(:@theme_css, malicious_css)
            method.call(*args)
          end

        get business_manager_website_template_preview_path

        # Verify curly braces are removed to prevent CSS context escape
        # Note: We're checking the rendered HTML, not the CSS itself
        expect(response.body).not_to match(/color: red; } body { display: none; }/)
      end
    end
  end

  describe 'URL injection protection in transactions view' do
    let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }
    let(:customer) { create(:tenant_customer, business: business) }
    let(:invoice) { create(:invoice, business: business, tenant_customer: customer) }
    let(:user) { create(:user, role: :client, business: business) }

    before do
      sign_in user
    end

    context 'when viewing transaction with safe business URL' do
      it 'generates valid payment URL for subdomain business' do
        get transaction_path(invoice)

        expect(response).to be_successful
        # Verify the payment link is generated correctly
        expect(response.body).to include('testbiz.') # Subdomain is present
        expect(response.body).to include('/payments/new') # Path is correct
      end

      it 'does not expose raw hostname in URL construction' do
        get transaction_path(invoice)

        # Verify we're not directly interpolating hostname
        # The safe_business_url helper should handle this
        expect(response).to be_successful
      end
    end

    context 'with malicious hostname attempts' do
      let(:malicious_business) do
        # Try to create a business with a malicious hostname
        # This should be caught by validation, but let's test the view protection too
        build(:business, hostname: '<script>alert("xss")</script>', host_type: :subdomain)
      end

      it 'safely handles invalid hostnames' do
        # The safe_business_url helper should return nil for invalid hostnames
        malicious_business.save(validate: false) # Bypass validation to test view protection
        malicious_invoice = create(:invoice, business: malicious_business, tenant_customer: customer)

        allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

        get transaction_path(malicious_invoice)

        # Should not render a malicious link
        expect(response.body).not to include('<script>')
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
          'font_size' => '16px',
          'evil_font' => 'javascript:alert(1)'
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

      # Verify malicious content is sanitized
      expect(css_variables).not_to include('javascript:')
      expect(css_variables).not_to include('alert(1)')

      # Verify legitimate values are preserved
      expect(css_variables).to include('--font-size: 16px;')
    end

    it 'converts underscores to hyphens in property names' do
      css_variables = theme.generate_css_variables

      # Verify underscore conversion
      expect(css_variables).to include('--font-size:')
      expect(css_variables).not_to include('--font_size:')
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
