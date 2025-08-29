# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubdomainAvailabilityService, type: :service do
  let(:service) { described_class }

  describe '.call' do
    context 'when subdomain is blank' do
      it 'returns unavailable' do
        result = service.call('')
        expect(result.available).to be_falsey
        expect(result.message).to eq('Subdomain cannot be blank')
      end
    end

    context 'when subdomain format is invalid' do
      it 'normalizes uppercase characters and can succeed' do
        result = service.call('BadSub')
        expect(result.available).to be_truthy
      end

      it 'returns unavailable for special characters' do
        result = service.call('bad_sub!')
        expect(result.available).to be_falsey
      end
    end

    context 'when subdomain is a reserved word' do
      it 'returns unavailable' do
        result = service.call('www')
        expect(result.available).to be_falsey
        expect(result.message).to eq('This subdomain is reserved')
      end
    end

    context 'when subdomain is already taken' do
      let!(:existing) { create(:business, subdomain: 'taken', hostname: 'taken') }

      it 'returns unavailable' do
        result = service.call('taken')
        expect(result.available).to be_falsey
        expect(result.message).to eq('This subdomain is already taken')
      end

      it 'is available when excluding the same business' do
        result = service.call('taken', exclude_business: existing)
        expect(result.available).to be_truthy
      end
    end

    context 'when subdomain is already used as hostname' do
      let!(:existing_hostname) { create(:business, hostname: 'hostonly', subdomain: 'different') }

      it 'returns unavailable' do
        result = service.call('hostonly')
        expect(result.available).to be_falsey
      end
    end

    context 'when subdomain is available' do
      it 'returns available' do
        result = service.call('newunique')
        expect(result.available).to be_truthy
        expect(result.message).to eq('Subdomain is available')
      end
    end
  end
end
