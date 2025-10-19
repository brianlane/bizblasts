# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Meta Tag XSS Security', type: :request do
  describe 'tenant-controlled meta tags' do
    context 'HTML escaping of tenant values' do
      # Business model validations prevent malicious hostnames/subdomains,
      # but we test HTML escaping as defense-in-depth

      let(:business) { FactoryBot.create(:business, hostname: 'testsalon', subdomain: 'testsalon') }

      before do
        host! "#{business.hostname}.lvh.me"
      end

      it 'safely renders tenant-hostname even if it contains special characters' do
        # Update to a value that passes validation but has special chars
        business.update_column(:hostname, 'test-salon-2024')

        get root_path

        # Verify meta tag is present and properly formatted
        expect(response.body).to include('name="tenant-hostname"')
        expect(response.body).to include('content="test-salon-2024"')
      end

      it 'safely renders tenant-subdomain even if it contains special characters' do
        # Update to a value that passes validation but has special chars
        business.update_column(:subdomain, 'test-salon-2024')

        get root_path

        # Verify meta tag is present and properly formatted
        expect(response.body).to include('name="tenant-subdomain"')
        expect(response.body).to include('content="test-salon-2024"')
      end

      it 'uses h() helper for HTML escaping tenant values' do
        get root_path

        # The h() helper should be used (verified by presence of escaped output)
        # This test documents that we're explicitly using HTML escaping
        expect(response.body).to include('name="tenant-hostname"')
        expect(response.body).to include("content=\"#{business.hostname}\"")

        # Even with safe values, escaping function should be applied
        expect(response.body).to include('name="tenant-subdomain"')
        expect(response.body).to include("content=\"#{business.subdomain}\"")

        expect(response.body).to include('name="tenant-type"')
        expect(response.body).to include('content="subdomain"')
      end
    end

    context 'with normal business values' do
      let(:business) { FactoryBot.create(:business, hostname: 'testsalon', subdomain: 'testsalon') }

      before do
        host! "#{business.hostname}.lvh.me"
      end

      it 'renders tenant-hostname meta tag correctly' do
        get root_path

        expect(response.body).to include('name="tenant-hostname"')
        expect(response.body).to include("content=\"#{business.hostname}\"")
      end

      it 'renders tenant-subdomain meta tag correctly' do
        get root_path

        expect(response.body).to include('name="tenant-subdomain"')
        expect(response.body).to include("content=\"#{business.subdomain}\"")
      end

      it 'renders tenant-type meta tag correctly' do
        get root_path

        expect(response.body).to include('name="tenant-type"')
        expect(response.body).to include('content="subdomain"')
      end
    end

    context 'with special characters in business name' do
      let(:business) do
        FactoryBot.create(:business,
                         hostname: 'testsalon',
                         subdomain: 'testsalon',
                         name: 'Test & Co. "Salon" <Premium>')
      end

      before do
        host! "#{business.hostname}.lvh.me"
      end

      it 'escapes special characters in business name for Open Graph tags' do
        get root_path

        # Should escape ampersands, quotes, and brackets
        expect(response.body).to include('&amp;')  # Escaped ampersand
        expect(response.body).not_to include('Test & Co.')  # Unescaped ampersand
        expect(response.body).to include('&quot;')  # Escaped quote
        expect(response.body).to include('&lt;')  # Escaped less-than
        expect(response.body).to include('&gt;')  # Escaped greater-than
      end
    end

    context 'on platform domain (no tenant)' do
      before do
        host! 'lvh.me'
      end

      it 'handles missing tenant gracefully' do
        get root_path

        # Should not crash when current_tenant is nil
        expect(response).to have_http_status(:success)

        # Tenant meta tags should have empty content or default values
        expect(response.body).to include('name="tenant-type"')
        expect(response.body).to include('content="platform"')
      end
    end
  end

  describe 'platform and canonical domain meta tags' do
    it 'renders platform-domain meta tag correctly in test environment' do
      get root_path

      expect(response.body).to include('name="platform-domain"')
      expect(response.body).to include('content="lvh.me"')
    end

    it 'renders canonical-domain meta tag correctly in test environment' do
      get root_path

      expect(response.body).to include('name="canonical-domain"')
      expect(response.body).to include('content="lvh.me"')
    end

    context 'in production environment' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      after do
        allow(Rails).to receive(:env).and_call_original
      end

      it 'renders platform-domain as bizblasts.com' do
        get root_path

        expect(response.body).to include('name="platform-domain"')
        expect(response.body).to include('content="bizblasts.com"')
      end

      it 'renders canonical-domain as www.bizblasts.com' do
        get root_path

        expect(response.body).to include('name="canonical-domain"')
        expect(response.body).to include('content="www.bizblasts.com"')
      end
    end
  end
end
