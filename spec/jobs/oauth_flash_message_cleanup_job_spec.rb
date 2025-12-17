# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthFlashMessageCleanupJob, type: :job do
  describe '#perform' do
    it 'cleans up used and expired OAuth flash messages' do
      # Create some test records
      used_token = OauthFlashMessage.create_with_token(notice: 'Used message')
      OauthFlashMessage.consume(used_token)

      expired_token = OauthFlashMessage.create_with_token(notice: 'Expired message')
      OauthFlashMessage.find_by(token: expired_token).update_columns(expires_at: 1.minute.ago)

      valid_token = OauthFlashMessage.create_with_token(notice: 'Valid message')

      expect(OauthFlashMessage.count).to eq(3)

      # Run the job
      described_class.new.perform

      # Only the valid token should remain
      expect(OauthFlashMessage.count).to eq(1)
      expect(OauthFlashMessage.find_by(token: valid_token)).to be_present
    end

    it 'logs the number of cleaned up records' do
      OauthFlashMessage.create_with_token(notice: 'Test')
      OauthFlashMessage.update_all(used: true)

      expect(Rails.logger).to receive(:info).with(/Cleaned up 1 old OAuth flash message records/)

      described_class.new.perform
    end
  end
end
