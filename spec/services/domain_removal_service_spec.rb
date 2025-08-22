# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainRemovalService, type: :service do
  let!(:business) do
    create(:business,
      tier: 'premium',
      host_type: 'custom_domain',
      hostname: 'example.com',
      subdomain: 'example',
      status: 'cname_active',
      render_domain_added: true,
      cname_monitoring_active: false
    )
  end

  let!(:owner) { create(:user, business: business, role: 'manager', email: 'owner@example.com') }
  let(:service) { described_class.new(business) }
  let(:render_service) { instance_double(RenderDomainService) }

  before do
    allow(RenderDomainService).to receive(:new).and_return(render_service)
  end

  describe '#remove_domain!' do
    let(:domain_data) { { 'id' => 'dom_123', 'name' => 'example.com' } }

    before do
      allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(domain_data)
      allow(render_service).to receive(:remove_domain).with('dom_123').and_return(true)
    end

    it 'completes domain removal successfully' do
      result = service.remove_domain!

      expect(result[:success]).to be true
      expect(result[:message]).to eq('Custom domain removed successfully')
      expect(result[:business_id]).to eq(business.id)
    end

    it 'stops active monitoring' do
      business.update!(cname_monitoring_active: true, status: 'cname_monitoring')

      service.remove_domain!

      business.reload
      expect(business.cname_monitoring_active).to be false
    end

    it 'removes domain from Render' do
      expect(render_service).to receive(:find_domain_by_name).with('example.com')
      expect(render_service).to receive(:remove_domain).with('dom_123')

      service.remove_domain!
    end

    it 'reverts business to subdomain hosting' do
      service.remove_domain!

      business.reload
      expect(business.host_type).to eq('subdomain')
      expect(business.status).to eq('active')
      expect(business.hostname).to eq('example')  # Should use subdomain value
      expect(business.render_domain_added).to be false
      expect(business.cname_setup_email_sent_at).to be_nil
      expect(business.cname_check_attempts).to eq(0)
    end

    it 'includes expected actions in result' do
      result = service.remove_domain!

      expect(result[:actions_taken]).to include(
        'Stopped DNS monitoring',
        'Removed domain from Render service',
        'Reverted to subdomain hosting',
        'Sent confirmation email'
      )
    end

    it 'returns correct reverted URL' do
      result = service.remove_domain!

      if Rails.env.production?
        expect(result[:reverted_to]).to eq('https://example.bizblasts.com')
      else
        expect(result[:reverted_to]).to eq('http://example.lvh.me:3000')
      end
    end

    context 'when domain not found in Render' do
      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
      end

      it 'continues with removal process' do
        expect(render_service).not_to receive(:remove_domain)

        result = service.remove_domain!

        expect(result[:success]).to be true
      end
    end

    context 'when Render removal fails' do
      before do
        allow(render_service).to receive(:remove_domain).and_raise(StandardError.new('Render API error'))
      end

      it 'continues with business reversion' do
        result = service.remove_domain!

        expect(result[:success]).to be true
        business.reload
        expect(business.host_type).to eq('subdomain')
      end
    end

    context 'when business has no subdomain' do
      before do
        business.update!(subdomain: nil)
      end

      it 'uses hostname as fallback' do
        service.remove_domain!

        business.reload
        expect(business.hostname).to eq('example.com')
      end
    end

    context 'when business has no subdomain or hostname' do
      before do
        business.update_columns(subdomain: nil, hostname: nil)
        allow(render_service).to receive(:find_domain_by_name).with(nil).and_return(nil)
      end

      it 'generates fallback hostname' do
        service.remove_domain!

        business.reload
        expect(business.hostname).to eq("business-#{business.id}")
      end
    end

    context 'when business update fails' do
      before do
        allow(business).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(business))
      end

      it 'returns error result' do
        result = service.remove_domain!

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:business_id]).to eq(business.id)
      end
    end
  end

  describe '#handle_tier_downgrade!' do
    context 'when downgrading from premium to free' do
      it 'removes domain' do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return({ 'id' => 'dom_123' })
        allow(render_service).to receive(:remove_domain).with('dom_123').and_return(true)
        result = service.handle_tier_downgrade!('free')

        expect(result[:success]).to be true
      end
    end

    context 'when staying on premium tier' do
      it 'does not remove domain' do
        expect(service).not_to receive(:remove_domain!)

        result = service.handle_tier_downgrade!('premium')

        expect(result[:success]).to be true
        expect(result[:message]).to include('No domain changes needed')
      end
    end

    context 'when business is not premium' do
      before do
        business.update!(tier: 'free', host_type: 'subdomain', hostname: 'example')
      end

      it 'does not remove domain' do
        expect(service).not_to receive(:remove_domain!)

        result = service.handle_tier_downgrade!('free')

        expect(result[:message]).to include('No domain changes needed')
      end
    end

    context 'when business does not have custom domain' do
      before do
        business.update!(host_type: 'subdomain', hostname: 'example')
      end

      it 'does not remove domain' do
        expect(service).not_to receive(:remove_domain!)

        result = service.handle_tier_downgrade!('free')

        expect(result[:message]).to include('No domain changes needed')
      end
    end
  end

  describe '#disable_domain!' do
    it 'disables domain without removing configuration' do
      result = service.disable_domain!

      expect(result[:success]).to be true
      expect(result[:message]).to include('disabled successfully')
      expect(result[:note]).to include('configuration preserved')

      business.reload
      expect(business.status).to eq('inactive')
      expect(business.cname_monitoring_active).to be false
      expect(business.hostname).to eq('example.com')  # Hostname preserved
    end

    context 'with active monitoring' do
      before do
        business.update!(cname_monitoring_active: true, status: 'cname_monitoring')
      end

      it 'stops monitoring' do
        service.disable_domain!

        business.reload
        expect(business.cname_monitoring_active).to be false
      end
    end
  end

  describe '#removal_preview' do
    it 'returns comprehensive preview information' do
      allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return({ 'id' => 'dom_123', 'verified' => true })
      preview = service.removal_preview

      expect(preview[:business_id]).to eq(business.id)
      expect(preview[:current_domain]).to eq('example.com')
      expect(preview[:current_status]).to eq('cname_active')
      expect(preview[:monitoring_active]).to be false
      expect(preview[:impact]).to be_a(Hash)
      expect(preview[:impact][:domain_access]).to include('example.com will no longer work')
    end

    it 'checks if Render domain exists' do
      expect(render_service).to receive(:find_domain_by_name).with('example.com')

      service.removal_preview
    end
  end

  describe 'private methods' do
    describe '#stop_monitoring_if_active' do
      context 'with active monitoring' do
        before do
          business.update!(cname_monitoring_active: true)
        end

        it 'stops monitoring' do
          service.send(:stop_monitoring_if_active)

          business.reload
          expect(business.cname_monitoring_active).to be false
        end
      end

      context 'without active monitoring' do
        it 'does nothing' do
          expect(business).not_to receive(:stop_cname_monitoring!)

          service.send(:stop_monitoring_if_active)
        end
      end
    end

    describe '#subdomain_url' do
      context 'with subdomain present' do
        it 'uses subdomain for URL' do
          url = service.send(:subdomain_url)

          if Rails.env.production?
            expect(url).to eq('https://example.bizblasts.com')
          else
            expect(url).to eq('http://example.lvh.me:3000')
          end
        end
      end

      context 'without subdomain but with hostname' do
        before do
          business.update!(subdomain: nil)
        end

        it 'uses hostname for URL' do
          url = service.send(:subdomain_url)

          if Rails.env.production?
            expect(url).to eq('https://example.com.bizblasts.com')
          else
            expect(url).to eq('http://example.com.lvh.me:3000')
          end
        end
      end

      context 'without subdomain or hostname' do
        before do
          business.update_columns(subdomain: nil, hostname: nil)
        end

        it 'generates fallback URL' do
          url = service.send(:subdomain_url)

          expected_subdomain = "business-#{business.id}"
          if Rails.env.production?
            expect(url).to eq("https://#{expected_subdomain}.bizblasts.com")
          else
            expect(url).to eq("http://#{expected_subdomain}.lvh.me:3000")
          end
        end
      end
    end

    describe '#check_render_domain_exists' do
      context 'when domain exists in Render' do
        before do
          allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return({ 'id' => 'dom_123' })
        end

        it 'returns true' do
          expect(service.send(:check_render_domain_exists)).to be true
        end
      end

      context 'when domain does not exist in Render' do
        before do
          allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
        end

        it 'returns false' do
          expect(service.send(:check_render_domain_exists)).to be false
        end
      end

      context 'when Render API fails' do
        before do
          allow(render_service).to receive(:find_domain_by_name).and_raise(StandardError.new('API error'))
        end

        it 'returns false' do
          expect(service.send(:check_render_domain_exists)).to be false
        end
      end
    end
  end
end