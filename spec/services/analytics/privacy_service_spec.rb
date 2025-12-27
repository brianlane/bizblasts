# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::PrivacyService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#do_not_track?' do
    it 'returns true when DNT header is set to 1' do
      request = double('request', headers: { 'DNT' => '1' })
      expect(service.do_not_track?(request)).to be true
    end

    it 'returns false when DNT header is not set' do
      request = double('request', headers: {})
      expect(service.do_not_track?(request)).to be false
    end

    it 'returns false when DNT header is 0' do
      request = double('request', headers: { 'DNT' => '0' })
      expect(service.do_not_track?(request)).to be false
    end
  end

  describe '#bot_request?' do
    it 'detects Googlebot' do
      request = double('request', user_agent: 'Mozilla/5.0 (compatible; Googlebot/2.1)')
      expect(service.bot_request?(request)).to be true
    end

    it 'detects common bots' do
      bot_agents = [
        'Mozilla/5.0 (compatible; bingbot/2.0)',
        'curl/7.64.1',
        'Screaming Frog SEO Spider',
        'facebookexternalhit/1.1'
      ]

      bot_agents.each do |agent|
        request = double('request', user_agent: agent)
        expect(service.bot_request?(request)).to be true
      end
    end

    it 'allows regular browsers' do
      request = double('request', user_agent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0')
      expect(service.bot_request?(request)).to be false
    end
  end

  describe '#anonymize_ip' do
    it 'anonymizes IPv4 addresses by zeroing last octet' do
      expect(service.anonymize_ip('192.168.1.100')).to eq('192.168.1.0')
      expect(service.anonymize_ip('10.0.0.255')).to eq('10.0.0.0')
    end

    it 'anonymizes IPv6 addresses by zeroing last 5 groups' do
      expect(service.anonymize_ip('2001:0db8:85a3:0000:0000:8a2e:0370:7334'))
        .to eq('2001:0db8:85a3:0:0:0:0:0')
    end

    it 'returns nil for blank IP' do
      expect(service.anonymize_ip(nil)).to be_nil
      expect(service.anonymize_ip('')).to be_nil
    end
  end

  describe '#should_disable_tracking?' do
    it 'returns true for DNT requests' do
      request = double('request', 
                       headers: { 'DNT' => '1' },
                       user_agent: 'Mozilla/5.0 Chrome/120.0')
      expect(service.should_disable_tracking?(request)).to be true
    end

    it 'returns true for bot requests' do
      request = double('request',
                       headers: {},
                       user_agent: 'Googlebot/2.1')
      expect(service.should_disable_tracking?(request)).to be true
    end

    it 'returns true for health check requests' do
      request = double('request',
                       headers: { 'X-Health-Check' => 'true' },
                       user_agent: 'Mozilla/5.0 Chrome/120.0')
      expect(service.should_disable_tracking?(request)).to be true
    end

    it 'returns false for regular requests' do
      request = double('request',
                       headers: {},
                       user_agent: 'Mozilla/5.0 Chrome/120.0')
      expect(service.should_disable_tracking?(request)).to be false
    end
  end

  describe '#delete_visitor_data' do
    before do
      ActsAsTenant.current_tenant = business
    end

    after do
      ActsAsTenant.current_tenant = nil
    end

    it 'deletes all data for a visitor fingerprint' do
      fingerprint = 'test-fingerprint-123'
      
      # Create test data
      create(:page_view, business: business, visitor_fingerprint: fingerprint)
      create(:click_event, business: business, visitor_fingerprint: fingerprint)
      create(:visitor_session, business: business, visitor_fingerprint: fingerprint)
      
      result = service.delete_visitor_data(fingerprint)
      
      expect(result[:page_views]).to eq(1)
      expect(result[:click_events]).to eq(1)
      expect(result[:visitor_sessions]).to eq(1)
      
      # Verify data is actually deleted
      expect(PageView.where(visitor_fingerprint: fingerprint).count).to eq(0)
      expect(ClickEvent.where(visitor_fingerprint: fingerprint).count).to eq(0)
      expect(VisitorSession.where(visitor_fingerprint: fingerprint).count).to eq(0)
    end

    it 'returns error without business context' do
      service_without_business = described_class.new(nil)
      result = service_without_business.delete_visitor_data('test-fingerprint')
      
      expect(result[:error]).to be_present
    end
  end

  describe '#export_visitor_data' do
    before do
      ActsAsTenant.current_tenant = business
    end

    after do
      ActsAsTenant.current_tenant = nil
    end

    it 'exports all data for a visitor' do
      fingerprint = 'export-test-123'
      
      create(:page_view, business: business, visitor_fingerprint: fingerprint, page_path: '/test')
      create(:visitor_session, business: business, visitor_fingerprint: fingerprint)
      
      export = service.export_visitor_data(fingerprint)
      
      expect(export[:visitor_fingerprint]).to eq(fingerprint)
      expect(export[:page_views]).to be_an(Array)
      expect(export[:sessions]).to be_an(Array)
      expect(export[:exported_at]).to be_present
    end
  end

  describe '#consent_requirements' do
    it 'requires explicit consent for GDPR countries' do
      gdpr_countries = %w[DE FR IT ES NL]
      
      gdpr_countries.each do |country|
        requirements = service.consent_requirements(country)
        expect(requirements[:requires_explicit_consent]).to be true
      end
    end

    it 'allows tracking by default for non-GDPR countries' do
      requirements = service.consent_requirements('US')
      expect(requirements[:tracking_allowed_by_default]).to be true
    end

    it 'always allows opt-out' do
      requirements = service.consent_requirements('US')
      expect(requirements[:opt_out_required]).to be true
    end
  end
end

