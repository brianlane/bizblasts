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
          hostname: 'example.com', 
          host_type_subdomain?: false, 
          host_type_custom_domain?: true
        )
        
        expect(TenantHost.host_for(business, request)).to eq('example.com')
      end

      it 'returns nil when hostname is empty' do
        business = double('Business', 
          hostname: '', 
          host_type_subdomain?: false, 
          host_type_custom_domain?: true
        )
        
        expect(TenantHost.host_for(business, request)).to be_nil
      end

      it 'returns nil when hostname is nil' do
        business = double('Business', 
          hostname: nil, 
          host_type_subdomain?: false, 
          host_type_custom_domain?: true
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
end