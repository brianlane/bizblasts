# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantHost do
  let(:request) { OpenStruct.new(protocol: 'http://', domain: 'lvh.me', port: 3000) }

  describe '.host_for' do
    context 'with subdomain businesses' do
      it 'generates correct host for valid subdomain' do
        business = double('Business', 
          subdomain: 'test', 
          hostname: 'backup', 
          host_type_subdomain?: true, 
          host_type_custom_domain?: false
        )
        
        expect(TenantHost.host_for(business, request)).to eq('test.lvh.me')
      end

      it 'falls back to hostname when subdomain is nil' do
        business = double('Business', 
          subdomain: nil, 
          hostname: 'backup', 
          host_type_subdomain?: true, 
          host_type_custom_domain?: false
        )
        
        expect(TenantHost.host_for(business, request)).to eq('backup.lvh.me')
      end

      it 'returns nil when both subdomain and hostname are nil' do
        business = double('Business', 
          subdomain: nil, 
          hostname: nil, 
          host_type_subdomain?: true, 
          host_type_custom_domain?: false
        )
        
        expect(TenantHost.host_for(business, request)).to be_nil
      end

      it 'returns nil when both subdomain and hostname are empty strings' do
        business = double('Business', 
          subdomain: '', 
          hostname: '', 
          host_type_subdomain?: true, 
          host_type_custom_domain?: false
        )
        
        expect(TenantHost.host_for(business, request)).to be_nil
      end

      it 'returns nil when subdomain is empty and hostname is nil' do
        business = double('Business', 
          subdomain: '', 
          hostname: nil, 
          host_type_subdomain?: true, 
          host_type_custom_domain?: false
        )
        
        expect(TenantHost.host_for(business, request)).to be_nil
      end
    end

    context 'with custom domain businesses' do
      it 'returns hostname for valid custom domain' do
        business = double('Business',
          hostname: 'custom-test.com',
          host_type_subdomain?: false,
          host_type_custom_domain?: true,
          custom_domain_allow?: true
        )

        expect(TenantHost.host_for(business, request)).to eq('custom-test.com')
      end

      it 'returns nil when hostname is empty' do
        business = double('Business',
          hostname: '',
          subdomain: nil,
          host_type_subdomain?: false,
          host_type_custom_domain?: true,
          custom_domain_allow?: false
        )

        expect(TenantHost.host_for(business, request)).to be_nil
      end

      it 'returns nil when hostname is nil' do
        business = double('Business',
          hostname: nil,
          subdomain: nil,
          host_type_subdomain?: false,
          host_type_custom_domain?: true,
          custom_domain_allow?: false
        )

        expect(TenantHost.host_for(business, request)).to be_nil
      end
    end

    it 'returns nil when business is nil' do
      expect(TenantHost.host_for(nil, request)).to be_nil
    end
  end

  describe '.url_for' do
    it 'returns just the path when host_for returns nil' do
      business = double('Business', 
        subdomain: nil, 
        hostname: nil, 
        host_type_subdomain?: true, 
        host_type_custom_domain?: false
      )
      
      expect(TenantHost.url_for(business, request, '/test')).to eq('/test')
    end

    it 'returns the path when host_for returns nil and path is root' do
      business = double('Business', 
        subdomain: nil, 
        hostname: nil, 
        host_type_subdomain?: true, 
        host_type_custom_domain?: false
      )
      
      expect(TenantHost.url_for(business, request, '/')).to eq('/')
    end
  end

  describe '.url_for_with_auth' do
    let(:subdomain_business) { create(:business, hostname: 'testbiz', subdomain: 'testbiz', host_type: 'subdomain') }
    let(:custom_domain_business) { create(:business, :with_custom_domain, hostname: 'custom-test.com', subdomain: 'example') }
    let(:mock_request) { double('request', host: 'test.host', port: 80, protocol: 'https://') }

    context 'with subdomain business' do
      it 'returns direct URL without auth bridge' do
        url = TenantHost.url_for_with_auth(subdomain_business, mock_request, '/services', user_signed_in: true)
        expect(url).to eq('https://testbiz.lvh.me/services')
      end

      it 'returns direct URL when user not signed in' do
        url = TenantHost.url_for_with_auth(subdomain_business, mock_request, '/services', user_signed_in: false)
        expect(url).to eq('https://testbiz.lvh.me/services')
      end
    end

    context 'with custom domain business' do
      context 'when user is signed in and on main domain' do
        it 'routes through auth bridge' do
          url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, '/services', user_signed_in: true)
          expected_target = CGI.escape('https://custom-test.com/services')
          expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
        end

        it 'properly encodes complex URLs with query parameters' do
          complex_path = '/booking/new?service_id=123&staff_id=456&date=2024-01-15'
          url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, complex_path, user_signed_in: true)

          expected_target = CGI.escape('https://custom-test.com/booking/new?service_id=123&staff_id=456&date=2024-01-15')
          expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
        end

        it 'handles root path correctly' do
          url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, '/', user_signed_in: true)
          expected_target = CGI.escape('https://custom-test.com/')
          expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
        end

        it 'handles empty path correctly' do
          url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, '', user_signed_in: true)
          expected_target = CGI.escape('https://custom-test.com')
          expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
        end
      end

      context 'when user is not signed in' do
        it 'returns direct URL without auth bridge' do
          url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, '/services', user_signed_in: false)
          expect(url).to eq('https://custom-test.com/services')
        end
      end

      context 'when already on custom domain' do
        let(:custom_domain_request) { double('request', host: 'custom-test.com', port: 443, protocol: 'https://') }

        it 'returns direct URL without auth bridge' do
          url = TenantHost.url_for_with_auth(custom_domain_business, custom_domain_request, '/services', user_signed_in: true)
          expect(url).to eq('https://custom-test.com/services')
        end
      end

      context 'when custom domain is not ready' do
        let(:unready_business) { create(:business, hostname: 'notready.com', host_type: 'custom_domain', domain_health_verified: false) }

        it 'falls back to subdomain even with auth bridge' do
          url = TenantHost.url_for_with_auth(unready_business, mock_request, '/services', user_signed_in: true)
          # Should fall back to subdomain and not use auth bridge
          expect(url).to include('.lvh.me')
          expect(url).not_to include('/auth/bridge')
        end
      end
    end

    context 'with nil business' do
      it 'returns the path as-is' do
        url = TenantHost.url_for_with_auth(nil, mock_request, '/services', user_signed_in: true)
        expect(url).to eq('/services')
      end
    end

    context 'in development environment' do
      before { allow(Rails.env).to receive(:production?).and_return(false) }

      let(:dev_request) { double('request', host: 'lvh.me', port: 3000, protocol: 'http://') }

      it 'uses development domain for auth bridge' do
        url = TenantHost.url_for_with_auth(custom_domain_business, dev_request, '/services', user_signed_in: true)
        expected_target = CGI.escape('http://custom-test.com/services')
        expect(url).to eq("http://lvh.me:3000/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
      end
    end

    context 'with different ports' do
      let(:port_request) { double('request', host: 'test.host', port: 8080, protocol: 'http://') }

      it 'includes port in auth bridge URL' do
        url = TenantHost.url_for_with_auth(custom_domain_business, port_request, '/services', user_signed_in: true)
        expected_target = CGI.escape('http://custom-test.com/services')
        expect(url).to eq("http://test.host:8080/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
      end
    end

    context 'URL encoding security' do
      it 'properly encodes dangerous characters in target URLs' do
        dangerous_path = '/search?q=<script>alert("xss")</script>&redirect=evil.com'
        url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, dangerous_path, user_signed_in: true)

        # The dangerous characters should be CGI escaped
        expect(url).to include(CGI.escape('https://custom-test.com/search?q=<script>alert("xss")</script>&redirect=evil.com'))
        expect(url).not_to include('<script>')
        expect(url).not_to include('</script>')
      end

      it 'handles unicode characters correctly' do
        unicode_path = '/café/naïve/résumé'
        url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, unicode_path, user_signed_in: true)

        # Unicode should be properly encoded
        expected_target = CGI.escape('https://custom-test.com/café/naïve/résumé')
        expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
      end

      it 'handles URLs with spaces and special characters' do
        special_path = '/path with spaces?param=value with & symbols'
        url = TenantHost.url_for_with_auth(custom_domain_business, mock_request, special_path, user_signed_in: true)

        expected_target = CGI.escape('https://custom-test.com/path with spaces?param=value with & symbols')
        expect(url).to eq("https://test.host/auth/bridge?target_url=#{expected_target}&business_id=#{custom_domain_business.id}")
      end
    end
  end

  describe '.main_domain?' do
    context 'in production' do
      before {
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:test?).and_return(false)
      }

      it 'recognizes production main domains' do
        expect(TenantHost.main_domain?('bizblasts.com')).to be_truthy
        expect(TenantHost.main_domain?('www.bizblasts.com')).to be_truthy
        expect(TenantHost.main_domain?('bizblasts.onrender.com')).to be_truthy
      end

      it 'rejects custom domains in production' do
        expect(TenantHost.main_domain?('custom-test.com')).to be_falsey
        expect(TenantHost.main_domain?('subdomain.bizblasts.com')).to be_falsey
        expect(TenantHost.main_domain?('lvh.me')).to be_falsey
      end
    end

    context 'in development/test' do
      before { 
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(false)
      }

      it 'recognizes development main domains' do
        expect(TenantHost.main_domain?('lvh.me')).to be_truthy
        expect(TenantHost.main_domain?('www.lvh.me')).to be_truthy
        expect(TenantHost.main_domain?('test.host')).to be_truthy
      end

      it 'handles case insensitivity' do
        expect(TenantHost.main_domain?('LVH.ME')).to be_truthy
        expect(TenantHost.main_domain?('TEST.HOST')).to be_truthy
      end

      it 'handles nil and empty strings gracefully' do
        expect(TenantHost.main_domain?(nil)).to be_falsey
        expect(TenantHost.main_domain?('')).to be_falsey
        expect(TenantHost.main_domain?('   ')).to be_falsey
      end
    end
  end
end