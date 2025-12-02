# frozen_string_literal: true

# Provide a SolidQueue::Pruner implementation until the gem ships one.
# Safely skipped if SolidQueue eventually introduces its own version.
module SolidQueue
  unless const_defined?(:Pruner)
    class Pruner
      DEFAULT_BATCH_SIZE = 1_000

      def self.run(older_than:, batch_size: DEFAULT_BATCH_SIZE)
        new(older_than:, batch_size:).run
      end

      def initialize(older_than:, batch_size: DEFAULT_BATCH_SIZE)
        @older_than = older_than
        @batch_size = batch_size
      end

      def run
        total_deleted = 0

        loop do
          job_ids = SolidQueue::Job.where("finished_at IS NOT NULL AND finished_at < ?", older_than)
                                   .limit(batch_size)
                                   .pluck(:id)
          break if job_ids.empty?

          prune_associated_records(job_ids)
          total_deleted += SolidQueue::Job.where(id: job_ids).delete_all
        end

        Rails.logger.info("[SolidQueue::Pruner] Deleted #{total_deleted} jobs older than #{older_than}")
        total_deleted
      end

      private

      attr_reader :older_than, :batch_size

      def prune_associated_records(job_ids)
        SolidQueue::BlockedExecution.where(job_id: job_ids).delete_all
        SolidQueue::ClaimedExecution.where(job_id: job_ids).delete_all
        SolidQueue::FailedExecution.where(job_id: job_ids).delete_all
        SolidQueue::ReadyExecution.where(job_id: job_ids).delete_all
        SolidQueue::RecurringExecution.where(job_id: job_ids).delete_all
        SolidQueue::ScheduledExecution.where(job_id: job_ids).delete_all
      end
    end
  end
end

