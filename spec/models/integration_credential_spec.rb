require 'rails_helper'

RSpec.describe IntegrationCredential, type: :model do
  let(:business) { create(:business) }

  it { should belong_to(:business) }
  it { should validate_presence_of(:provider) }
  it { should validate_presence_of(:config) }

  describe 'enum provider' do
    it 'accepts valid values' do
      expect(build(:integration_credential, provider: :twilio)).to be_valid
      expect(build(:integration_credential, provider: :mailgun)).to be_valid
      expect(build(:integration_credential, provider: :sendgrid)).to be_valid
    end
    it 'rejects invalid values' do
      expect {
        build(:integration_credential, provider: 'invalid')
      }.to raise_error(ArgumentError)
    end
  end
end 