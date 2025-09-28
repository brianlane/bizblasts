# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvalidatedSessionCleanupJob, type: :job do
  include ActiveJob::TestHelper

  describe '#perform' do
    context 'when expired sessions exist' do
      let!(:active_sessions) { create_list(:invalidated_session, 3, expires_at: 2.hours.from_now) }
      let!(:expired_sessions) { create_list(:invalidated_session, 5, expires_at: 1.hour.ago) }

      it 'completes successfully and cleans up expired sessions' do
        expect {
          perform_enqueued_jobs do
            InvalidatedSessionCleanupJob.perform_later
          end
        }.to change(InvalidatedSession, :count).by(-5)

        # Verify active sessions remain
        active_sessions.each do |session|
          expect(InvalidatedSession.exists?(session.id)).to be true
        end

        # Verify expired sessions are gone
        expired_sessions.each do |session|
          expect(InvalidatedSession.exists?(session.id)).to be false
        end
      end

      it 'logs start and completion with cleanup count' do
        expect(Rails.logger).to receive(:info).with(/Starting cleanup/)
        expect(Rails.logger).to receive(:info).with("[InvalidatedSession] Cleaned up 5 expired entries")

        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later
        end
      end

      it 'calls InvalidatedSession.cleanup_expired!' do
        expect(InvalidatedSession).to receive(:cleanup_expired!).and_call_original

        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later
        end
      end

      it 'schedules the next cleanup job when scheduling is enabled' do
        expect {
          perform_enqueued_jobs do
            InvalidatedSessionCleanupJob.perform_later(schedule_next: true)
          end
        }.to have_enqueued_job(InvalidatedSessionCleanupJob).at(6.hours.from_now)
      end
    end

    context 'when no expired sessions exist' do
      let!(:active_sessions) { create_list(:invalidated_session, 3, expires_at: 2.hours.from_now) }

      it 'completes successfully without removing any sessions' do
        expect {
          perform_enqueued_jobs do
            InvalidatedSessionCleanupJob.perform_later
          end
        }.not_to change(InvalidatedSession, :count)
      end

      it 'logs completion with zero cleanup count' do
        expect(Rails.logger).to receive(:info).with(/Starting cleanup/)
        expect(Rails.logger).to receive(:info).with(/Completed in \d+\.\d+s, cleaned 0 expired sessions/)

        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later
        end
      end

      it 'still schedules the next cleanup job when scheduling is enabled' do
        expect {
          perform_enqueued_jobs do
            InvalidatedSessionCleanupJob.perform_later(schedule_next: true)
          end
        }.to have_enqueued_job(InvalidatedSessionCleanupJob).at(6.hours.from_now)
      end
    end

    context 'when cleanup fails' do
      before do
        create_list(:invalidated_session, 2, expires_at: 1.hour.ago)
      end

      it 'logs error and re-raises exception' do
        allow(InvalidatedSession).to receive(:cleanup_expired!).and_raise(StandardError.new("Database error"))

        expect(Rails.logger).to receive(:info).with(/Starting cleanup/)
        expect(Rails.logger).to receive(:error).with(/Failed: Database error/)

        expect {
          perform_enqueued_jobs do
            InvalidatedSessionCleanupJob.perform_later
          end
        }.to raise_error(StandardError, "Database error")
      end

      it 'does not schedule next job when cleanup fails' do
        allow(InvalidatedSession).to receive(:cleanup_expired!).and_raise(StandardError.new("Database error"))

        expect {
          begin
            InvalidatedSessionCleanupJob.new.perform(schedule_next: true)
          rescue StandardError
            # Expected to raise
          end
        }.not_to have_enqueued_job(InvalidatedSessionCleanupJob)
      end
    end

    context 'performance and timing' do
      let!(:many_expired_sessions) { create_list(:invalidated_session, 100, expires_at: 1.hour.ago) }

      it 'measures and logs execution time' do
        start_time = Time.current

        expect(Rails.logger).to receive(:info) do |message|
          expect(message).to match("[InvalidatedSession] Cleaned up 100 expired entries")

          # Verify the timing is reasonable (should be very fast)
          duration_match = message.match(/Completed in (\d+\.\d+)s/)
          duration = duration_match[1].to_f if duration_match
          expect(duration).to be < 5.0 # Should complete in under 5 seconds
        end

        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later
        end
      end
    end
  end

  describe 'job configuration' do
    it 'is configured with default queue' do
      expect(InvalidatedSessionCleanupJob.queue_name).to eq('default')
    end

    it 'has retry configuration' do
      job = InvalidatedSessionCleanupJob.new
      expect(job.class.retry_on_args).to include(StandardError)
    end

    it 'performs job asynchronously' do
      expect {
        InvalidatedSessionCleanupJob.perform_later
      }.to have_enqueued_job(InvalidatedSessionCleanupJob)
    end
  end

  describe 'recurring job behavior' do
    it 'creates a self-sustaining cleanup cycle when scheduling is enabled' do
      # First job should schedule the next one
      expect {
        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later(schedule_next: true)
        end
      }.to have_enqueued_job(InvalidatedSessionCleanupJob).at(6.hours.from_now)

      # Clear the queue to simulate time passing
      clear_enqueued_jobs

      # Simulate the next scheduled job running
      expect {
        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later(schedule_next: true)
        end
      }.to have_enqueued_job(InvalidatedSessionCleanupJob).at(6.hours.from_now)
    end

    it 'schedules next job even when no cleanup is needed' do
      # No expired sessions exist
      expect(InvalidatedSession.expired.count).to eq(0)

      expect {
        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later(schedule_next: true)
        end
      }.to have_enqueued_job(InvalidatedSessionCleanupJob).at(6.hours.from_now)
    end

    it 'does not schedule next job when scheduling is disabled' do
      expect {
        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later(schedule_next: false)
        end
      }.not_to have_enqueued_job(InvalidatedSessionCleanupJob)
    end
  end

  describe 'integration with InvalidatedSession model' do
    let!(:user) { create(:user) }
    let!(:recent_blacklisted) { create(:invalidated_session, user: user, expires_at: 23.hours.from_now) }
    let!(:old_blacklisted) { create(:invalidated_session, user: user, expires_at: 1.hour.ago) }

    it 'properly integrates with the session blacklist system' do
      # Verify initial state
      expect(InvalidatedSession.session_blacklisted?(recent_blacklisted.session_token)).to be true
      expect(InvalidatedSession.session_blacklisted?(old_blacklisted.session_token)).to be false

      # Run cleanup
      perform_enqueued_jobs do
        InvalidatedSessionCleanupJob.perform_later
      end

      # Verify recent blacklisted session is still there
      expect(InvalidatedSession.exists?(recent_blacklisted.id)).to be true
      expect(InvalidatedSession.session_blacklisted?(recent_blacklisted.session_token)).to be true

      # Verify old blacklisted session is cleaned up
      expect(InvalidatedSession.exists?(old_blacklisted.id)).to be false
    end

    it 'maintains referential integrity during cleanup' do
      # Ensure the user still exists after cleanup
      user_id = user.id

      perform_enqueued_jobs do
        InvalidatedSessionCleanupJob.perform_later
      end

      expect(User.exists?(user_id)).to be true
      expect(recent_blacklisted.reload.user).to eq(user)
    end
  end

  describe 'edge cases' do
    it 'handles empty invalidated_sessions table gracefully' do
      expect(InvalidatedSession.count).to eq(0)

      expect {
        perform_enqueued_jobs do
          InvalidatedSessionCleanupJob.perform_later
        end
      }.not_to raise_error

      expect(InvalidatedSession.count).to eq(0)
    end

    it 'handles sessions that expire exactly at cleanup time' do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      # Create session that expires exactly now
      session_expiring_now = create(:invalidated_session, expires_at: freeze_time)

      perform_enqueued_jobs do
        InvalidatedSessionCleanupJob.perform_later
      end

      # Session expiring exactly now should be cleaned up (expires_at <= Time.current)
      expect(InvalidatedSession.exists?(session_expiring_now.id)).to be false
    end
  end
end
