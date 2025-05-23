require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:business) { create(:business) }
  let(:tenant) { create(:tenant_customer, business: business) }

  describe '.calculate_stripe_fee_cents' do
    it 'calculates 3% plus 30¢ correctly' do
      expect(described_class.send(:calculate_stripe_fee_cents, 1000)).to eq((1000 * 0.03).round + 30)
    end
  end

  describe '.calculate_platform_fee_cents' do
    it 'uses 5% for free tier' do
      business.update!(tier: 'free')
      expect(described_class.send(:calculate_platform_fee_cents, 1000, business)).to eq((1000 * 0.05).round)
    end

    it 'uses 3% for premium tier' do
      business.update!(tier: 'premium')
      expect(described_class.send(:calculate_platform_fee_cents, 1000, business)).to eq((1000 * 0.03).round)
    end
  end

  describe '.get_stripe_price_id' do
    it 'returns correct ENV value for standard' do
      allow(ENV).to receive(:[]).with('STRIPE_STANDARD_PRICE_ID').and_return('price_std')
      expect(described_class.get_stripe_price_id('standard')).to eq('price_std')
    end
    it 'returns correct ENV value for premium' do
      allow(ENV).to receive(:[]).with('STRIPE_PREMIUM_PRICE_ID').and_return('price_prem')
      expect(described_class.get_stripe_price_id('premium')).to eq('price_prem')
    end
  end
end 