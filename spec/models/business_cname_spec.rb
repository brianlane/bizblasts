# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business, type: :model do
  describe 'CNAME domain functionality' do
    let(:business) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'example.com') }

    describe 'status enum' do
      it 'includes CNAME statuses' do
        expect(Business.statuses.keys).to include(
          'active', 'inactive', 'suspended',
          'cname_pending', 'cname_monitoring', 'cname_active', 'cname_timeout'
        )
      end

      it 'defaults to active status' do
        new_business = Business.new
        expect(new_business.status).to eq('active')
      end

      it 'supports CNAME status transitions' do
        business.update!(status: 'cname_pending')
        expect(business.cname_pending?).to be true

        business.update!(status: 'cname_monitoring')
        expect(business.cname_monitoring?).to be true

        business.update!(status: 'cname_active')
        expect(business.cname_active?).to be true
      end
    end

    describe 'scopes' do
      let!(:pending_business) { create(:business, status: 'cname_pending') }
      let!(:monitoring_business) { create(:business, status: 'cname_monitoring', cname_monitoring_active: true) }
      let!(:active_business) { create(:business, status: 'cname_active') }
      let!(:inactive_business) { create(:business, status: 'active') }

      describe '.cname_pending' do
        it 'returns businesses with pending status' do
          expect(Business.cname_pending).to contain_exactly(pending_business)
        end
      end

      describe '.cname_monitoring' do
        it 'returns businesses with monitoring status' do
          expect(Business.cname_monitoring).to contain_exactly(monitoring_business)
        end
      end

      describe '.monitoring_needed' do
        it 'returns businesses that need active monitoring' do
          expect(Business.monitoring_needed).to contain_exactly(monitoring_business)
        end

        it 'excludes businesses with inactive monitoring' do
          monitoring_business.update!(cname_monitoring_active: false)
          expect(Business.monitoring_needed).to be_empty
        end
      end
    end

    describe '#start_cname_monitoring!' do
      it 'starts monitoring for eligible business' do
        business.start_cname_monitoring!

        expect(business.status).to eq('cname_monitoring')
        expect(business.cname_monitoring_active).to be true
        expect(business.cname_check_attempts).to eq(0)
      end

      it 'fails for non-premium business' do
        business.update!(tier: 'free')

        result = business.start_cname_monitoring!

        expect(result).to be false
        expect(business.status).not_to eq('cname_monitoring')
      end

      it 'fails for subdomain business' do
        business.update!(host_type: 'subdomain')

        result = business.start_cname_monitoring!

        expect(result).to be false
        expect(business.status).not_to eq('cname_monitoring')
      end
    end

    describe '#stop_cname_monitoring!' do
      before do
        business.update!(
          status: 'cname_monitoring',
          cname_monitoring_active: true
        )
      end

      it 'stops monitoring and updates status' do
        business.stop_cname_monitoring!

        expect(business.cname_monitoring_active).to be false
        expect(business.status).to eq('active')
      end

      context 'when business has cname_active status' do
        before do
          business.update!(status: 'cname_active')
        end

        it 'maintains cname_active status' do
          business.stop_cname_monitoring!

          expect(business.status).to eq('cname_active')
          expect(business.cname_monitoring_active).to be false
        end
      end
    end

    describe '#cname_due_for_check?' do
      context 'with no previous attempts' do
        before do
          business.update!(cname_monitoring_active: true, cname_check_attempts: 0)
        end

        it 'returns true for first check' do
          expect(business.cname_due_for_check?).to be true
        end
      end

      context 'with previous attempts' do
        before do
          business.update!(
            cname_monitoring_active: true,
            cname_check_attempts: 3,
            updated_at: 6.minutes.ago
          )
        end

        it 'returns true after 5 minutes' do
          expect(business.cname_due_for_check?).to be true
        end

        it 'returns false before 5 minutes' do
          business.update!(updated_at: 3.minutes.ago)
          expect(business.cname_due_for_check?).to be false
        end
      end

      context 'with maximum attempts reached' do
        before do
          business.update!(cname_monitoring_active: true, cname_check_attempts: 12)
        end

        it 'returns false' do
          expect(business.cname_due_for_check?).to be false
        end
      end

      context 'with inactive monitoring' do
        before do
          business.update!(cname_monitoring_active: false)
        end

        it 'returns false' do
          expect(business.cname_due_for_check?).to be false
        end
      end
    end

    describe '#increment_cname_check!' do
      before do
        business.update!(cname_check_attempts: 5)
      end

      it 'increments check attempts counter' do
        business.increment_cname_check!

        business.reload
        expect(business.cname_check_attempts).to eq(6)
      end
    end

    describe '#cname_timeout!' do
      before do
        business.update!(status: 'cname_monitoring', cname_monitoring_active: true)
      end

      it 'sets timeout status and stops monitoring' do
        business.cname_timeout!

        expect(business.status).to eq('cname_timeout')
        expect(business.cname_monitoring_active).to be false
      end
    end

    describe '#cname_success!' do
      before do
        business.update!(status: 'cname_monitoring', cname_monitoring_active: true)
      end

      it 'sets active status and stops monitoring' do
        business.cname_success!

        expect(business.status).to eq('cname_active')
        expect(business.cname_monitoring_active).to be false
      end
    end

    describe '#can_setup_custom_domain?' do
      context 'with eligible business' do
        it 'returns true' do
          expect(business.can_setup_custom_domain?).to be true
        end
      end

      context 'with non-premium business' do
        before { business.update!(tier: 'free') }

        it 'returns false' do
          expect(business.can_setup_custom_domain?).to be false
        end
      end

      context 'with subdomain business' do
        before { business.update!(host_type: 'subdomain') }

        it 'returns false' do
          expect(business.can_setup_custom_domain?).to be false
        end
      end

      context 'with already active domain' do
        before { business.update!(status: 'cname_active') }

        it 'returns false' do
          expect(business.can_setup_custom_domain?).to be false
        end
      end
    end

    describe '#handle_tier_downgrade callback' do
      let(:removal_service) { instance_double(DomainRemovalService) }

      before do
        allow(DomainRemovalService).to receive(:new).with(business).and_return(removal_service)
        allow(removal_service).to receive(:handle_tier_downgrade!).and_return(success: true)
      end

      context 'when downgrading from premium to free' do
        before do
          business.update!(tier: 'premium')
        end

        it 'triggers domain removal' do
          expect(removal_service).to receive(:handle_tier_downgrade!).with('free')

          business.update!(tier: 'free')
        end
      end

      context 'when staying on premium tier' do
        before do
          business.update!(tier: 'premium')
        end

        it 'does not trigger domain removal' do
          expect(DomainRemovalService).not_to receive(:new)

          business.update!(tier: 'premium', name: 'Updated Name')
        end
      end

      context 'when business has subdomain hosting' do
        before do
          business.update!(tier: 'premium', host_type: 'subdomain')
        end

        it 'does not trigger domain removal' do
          expect(DomainRemovalService).not_to receive(:new)

          business.update!(tier: 'free')
        end
      end

      context 'when tier is not changing' do
        it 'does not trigger domain removal' do
          expect(DomainRemovalService).not_to receive(:new)

          business.update!(name: 'Updated Name')
        end
      end
    end

    describe 'database columns' do
      it 'has CNAME monitoring fields' do
        expect(business).to respond_to(:cname_setup_email_sent_at)
        expect(business).to respond_to(:cname_monitoring_active)
        expect(business).to respond_to(:cname_check_attempts)
        expect(business).to respond_to(:render_domain_added)
      end

      it 'has correct default values' do
        new_business = Business.new
        expect(new_business.cname_monitoring_active).to be false
        expect(new_business.cname_check_attempts).to eq(0)
        expect(new_business.render_domain_added).to be false
      end
    end

    describe 'validations with CNAME fields' do
      it 'validates custom domain format for custom_domain host_type' do
        business.hostname = 'invalid-domain'

        expect(business).not_to be_valid
        expect(business.errors[:hostname]).to include('is not a valid domain name')
      end

      it 'allows valid custom domain format' do
        business.update!(hostname: 'example.com')

        expect(business).to be_valid
      end

      it 'prevents free tier from using custom domains' do
        free_business = build(:business, tier: 'free', host_type: 'custom_domain')

        expect(free_business).not_to be_valid
        expect(free_business.errors[:host_type]).to include("must be 'subdomain' for Free and Standard tiers")
      end
    end
  end
end