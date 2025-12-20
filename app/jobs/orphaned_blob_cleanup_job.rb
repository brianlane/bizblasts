# frozen_string_literal: true

# Background job for cleaning up orphaned ActiveStorage blobs.
# This job runs periodically to remove blobs that are no longer
# attached to any records, typically from failed uploads or
# interrupted crop operations.
#
# @example Enqueue manually
#   OrphanedBlobCleanupJob.perform_later
#
# @example Schedule with solid_queue (in config/recurring.yml)
#   orphaned_blob_cleanup:
#     class: OrphanedBlobCleanupJob
#     cron: "0 3 * * *"  # Run daily at 3 AM
class OrphanedBlobCleanupJob < ApplicationJob
  queue_as :maintenance

  # Minimum age (in hours) before a blob is considered orphaned
  # This prevents deletion of blobs that are in the middle of being processed
  ORPHAN_AGE_THRESHOLD = 24.hours

  # Maximum number of blobs to process in a single run
  BATCH_SIZE = 1000

  # Minimum age for variant records to be cleaned up
  VARIANT_AGE_THRESHOLD = 48.hours

  def perform(options = {})
    dry_run = options.fetch(:dry_run, false)
    verbose = options.fetch(:verbose, false)

    Rails.logger.info "[OrphanedBlobCleanupJob] Starting cleanup (dry_run: #{dry_run})"

    stats = {
      orphaned_blobs_found: 0,
      orphaned_blobs_deleted: 0,
      orphaned_variants_found: 0,
      orphaned_variants_deleted: 0,
      errors: []
    }

    # Clean up orphaned blobs
    cleanup_orphaned_blobs(stats, dry_run, verbose)

    # Clean up orphaned variant records
    cleanup_orphaned_variants(stats, dry_run, verbose)

    # Log results
    log_results(stats, dry_run)

    stats
  end

  private

  def cleanup_orphaned_blobs(stats, dry_run, verbose)
    # Find blobs that have no attachments and are older than threshold
    orphaned_blobs = ActiveStorage::Blob
      .left_outer_joins(:attachments)
      .where(active_storage_attachments: { id: nil })
      .where("active_storage_blobs.created_at < ?", ORPHAN_AGE_THRESHOLD.ago)

    # Get total count before limiting
    total_orphaned = orphaned_blobs.count
    stats[:orphaned_blobs_found] = [total_orphaned, BATCH_SIZE].min

    # Use in_batches with a limit to respect BATCH_SIZE
    # find_each ignores limit(), so we manually limit iterations
    processed = 0
    orphaned_blobs.find_each do |blob|
      break if processed >= BATCH_SIZE
      processed += 1

      Rails.logger.info "[OrphanedBlobCleanupJob] Found orphaned blob: #{blob.id} (#{blob.filename})" if verbose

      next if dry_run

      begin
        blob.purge
        stats[:orphaned_blobs_deleted] += 1
        Rails.logger.debug "[OrphanedBlobCleanupJob] Purged blob #{blob.id}"
      rescue StandardError => e
        stats[:errors] << { blob_id: blob.id, error: e.message }
        Rails.logger.error "[OrphanedBlobCleanupJob] Failed to purge blob #{blob.id}: #{e.message}"
      end
    end
  end

  def cleanup_orphaned_variants(stats, dry_run, verbose)
    # Clean up variant records that point to non-existent blobs
    # This can happen if a blob is deleted but its variants aren't properly cleaned up
    # Note: We only filter orphaned variants without timestamp constraint since
    # active_storage_variant_records doesn't have created_at by default
    orphaned_variants = ActiveStorage::VariantRecord
      .left_outer_joins(:blob)
      .where(active_storage_blobs: { id: nil })

    # Get total count before limiting
    total_orphaned = orphaned_variants.count
    stats[:orphaned_variants_found] = [total_orphaned, BATCH_SIZE].min

    # Use find_each with manual limit to respect BATCH_SIZE
    processed = 0
    orphaned_variants.find_each do |variant|
      break if processed >= BATCH_SIZE
      processed += 1

      Rails.logger.info "[OrphanedBlobCleanupJob] Found orphaned variant: #{variant.id}" if verbose

      next if dry_run

      begin
        variant.destroy
        stats[:orphaned_variants_deleted] += 1
        Rails.logger.debug "[OrphanedBlobCleanupJob] Deleted variant record #{variant.id}"
      rescue StandardError => e
        stats[:errors] << { variant_id: variant.id, error: e.message }
        Rails.logger.error "[OrphanedBlobCleanupJob] Failed to delete variant #{variant.id}: #{e.message}"
      end
    end
  end

  def log_results(stats, dry_run)
    prefix = dry_run ? "[DRY RUN] " : ""

    Rails.logger.info "[OrphanedBlobCleanupJob] #{prefix}Cleanup complete:"
    Rails.logger.info "  Orphaned blobs found: #{stats[:orphaned_blobs_found]}"
    Rails.logger.info "  Orphaned blobs deleted: #{stats[:orphaned_blobs_deleted]}"
    Rails.logger.info "  Orphaned variants found: #{stats[:orphaned_variants_found]}"
    Rails.logger.info "  Orphaned variants deleted: #{stats[:orphaned_variants_deleted]}"

    if stats[:errors].any?
      Rails.logger.warn "[OrphanedBlobCleanupJob] #{prefix}Errors: #{stats[:errors].count}"
      stats[:errors].each do |error|
        Rails.logger.warn "  - #{error.inspect}"
      end
    end
  end
end
