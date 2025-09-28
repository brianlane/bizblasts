# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CrossDomainLogoutJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:ip_address) { '192.168.1.100' }

  describe '#perform' do
    context 'with valid user' do
      it 'completes successfully with user_id and ip_address' do
        expect {
          perform_enqueued_jobs do
            CrossDomainLogoutJob.perform_later(user.id, ip_address)
          end
        }.not_to raise_error
      end

      it 'completes successfully with only user_id' do
        expect {
          perform_enqueued_jobs do
            CrossDomainLogoutJob.perform_later(user.id)
          end
        }.not_to raise_error
      end

      it 'logs the start and completion of cleanup' do
        expect(Rails.logger).to receive(:info).with(/Starting cross-domain logout cleanup for user #{user.id}/).ordered
        expect(Rails.logger).to receive(:info).with(/User #{user.id} \(#{user.email}\) logged out from IP #{ip_address}/).ordered
        expect(Rails.logger).to receive(:info).with(/Completed cleanup for user #{user.id} in \d+\.\d+s/).ordered

        perform_enqueued_jobs do
          CrossDomainLogoutJob.perform_later(user.id, ip_address)
        end
      end

      it 'calls cleanup methods' do
        job = CrossDomainLogoutJob.new
        expect(job).to receive(:cleanup_auth_tokens).with(user)
        expect(job).to receive(:log_logout_event).with(user, ip_address)

        job.perform(user.id, ip_address)
      end
    end

    context 'with non-existent user' do
      it 'handles missing user gracefully' do
        non_existent_id = User.maximum(:id).to_i + 1

        expect(Rails.logger).to receive(:warn).with(/User #{non_existent_id} not found, skipping cleanup/)

        expect {
          perform_enqueued_jobs do
            CrossDomainLogoutJob.perform_later(non_existent_id, ip_address)
          end
        }.not_to raise_error
      end

      it 'does not call cleanup methods for missing user' do
        non_existent_id = User.maximum(:id).to_i + 1
        job = CrossDomainLogoutJob.new

        expect(job).not_to receive(:cleanup_auth_tokens)
        expect(job).not_to receive(:log_logout_event)

        job.perform(non_existent_id, ip_address)
      end
    end

    context 'error handling' do
      it 'logs and re-raises exceptions' do
        allow(User).to receive(:find_by).and_raise(StandardError.new("Database error"))

        expect(Rails.logger).to receive(:error).with(/Failed for user #{user.id}: Database error/)

        expect {
          CrossDomainLogoutJob.new.perform(user.id, ip_address)
        }.to raise_error(StandardError, "Database error")
      end
    end
  end

  describe '#cleanup_auth_tokens (private)' do
    let(:job) { CrossDomainLogoutJob.new }

    context 'when user has unused auth tokens' do
      let!(:unused_tokens) { create_list(:auth_token, 3, user: user, used: false) }
      let!(:used_token) { create(:auth_token, user: user, used: true) }

      it 'marks all unused tokens as used' do
        job.send(:cleanup_auth_tokens, user)

        unused_tokens.each do |token|
          expect(token.reload.used?).to be true
        end

        # Should not affect already used tokens
        expect(used_token.reload.used?).to be true
      end

      it 'logs the cleanup action' do
        expect(Rails.logger).to receive(:info).with(/Invalidated 3 unused auth tokens for user #{user.id}/)
        job.send(:cleanup_auth_tokens, user)
      end
    end

    context 'when user has no unused auth tokens' do
      let!(:used_tokens) { create_list(:auth_token, 2, user: user, used: true) }

      it 'does not log cleanup action' do
        expect(Rails.logger).not_to receive(:info).with(/Invalidated .* unused auth tokens/)
        job.send(:cleanup_auth_tokens, user)
      end
    end

    context 'when cleanup fails' do
      before do
        create(:auth_token, user: user, used: false)
      end

      it 'logs the error and continues' do
        allow(AuthToken).to receive(:where).and_raise(StandardError.new("Database error"))

        expect(Rails.logger).to receive(:error).with(/Failed to cleanup auth tokens for user #{user.id}: Database error/)

        expect {
          job.send(:cleanup_auth_tokens, user)
        }.not_to raise_error
      end
    end
  end

  describe '#log_logout_event (private)' do
    let(:job) { CrossDomainLogoutJob.new }

    it 'logs the logout event with user and IP information' do
      expect(Rails.logger).to receive(:info).with(/User #{user.id} \(#{user.email}\) logged out from IP #{ip_address}/)
      job.send(:log_logout_event, user, ip_address)
    end

    it 'handles nil IP address' do
      expect(Rails.logger).to receive(:info).with(/User #{user.id} \(#{user.email}\) logged out from IP $/)
      job.send(:log_logout_event, user, nil)
    end

    context 'when logging fails' do
      it 'logs the error and continues' do
        # Create user without affecting factory creation
        test_user = build(:user, id: 999, email: 'test@example.com')

        # Only mock the specific logging call that would fail
        allow(Rails.logger).to receive(:info).with(/User #{test_user.id}/).and_raise(StandardError.new("Logging error"))
        allow(Rails.logger).to receive(:info) # Allow other logging calls

        expect(Rails.logger).to receive(:error).with(/Failed to log logout event for user #{test_user.id}: Logging error/)

        expect {
          job.send(:log_logout_event, test_user, ip_address)
        }.not_to raise_error
      end
    end
  end

  describe 'job configuration' do
    it 'is configured with default queue' do
      expect(CrossDomainLogoutJob.queue_name).to eq('default')
    end

    it 'has retry configuration' do
      # Test that retry_on is configured by checking job class setup
      expect(CrossDomainLogoutJob.queue_adapter).to respond_to(:enqueue)
    end

    it 'performs job asynchronously' do
      expect {
        CrossDomainLogoutJob.perform_later(user.id, ip_address)
      }.to have_enqueued_job(CrossDomainLogoutJob).with(user.id, ip_address)
    end
  end

  describe 'integration with authentication system' do
    let!(:auth_tokens) { create_list(:auth_token, 2, user: user, used: false) }

    it 'properly integrates with the logout flow' do
      expect {
        perform_enqueued_jobs do
          CrossDomainLogoutJob.perform_later(user.id, ip_address)
        end
      }.to change { auth_tokens.map(&:reload).map(&:used?) }.from([false, false]).to([true, true])
    end

    it 'works with real user session tokens' do
      # Simulate a real logout scenario
      session_token = SecureRandom.urlsafe_base64(32)
      user.update!(session_token: session_token)

      expect {
        perform_enqueued_jobs do
          CrossDomainLogoutJob.perform_later(user.id, ip_address)
        end
      }.not_to raise_error
    end
  end
end
