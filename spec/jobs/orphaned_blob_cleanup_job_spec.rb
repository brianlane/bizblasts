# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrphanedBlobCleanupJob, type: :job do
  include ActiveJob::TestHelper

  describe "#perform" do
    context "with orphaned blobs" do
      let!(:orphaned_blob) do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("test content"),
          filename: "orphaned.txt",
          content_type: "text/plain"
        )
        # Backdate the blob to be older than the threshold
        blob.update_column(:created_at, 2.days.ago)
        blob
      end

      it "deletes orphaned blobs older than threshold" do
        expect {
          described_class.perform_now
        }.to change { ActiveStorage::Blob.exists?(orphaned_blob.id) }.from(true).to(false)
      end

      it "returns stats with deletion count" do
        stats = described_class.perform_now

        expect(stats[:orphaned_blobs_found]).to be >= 1
        expect(stats[:orphaned_blobs_deleted]).to be >= 1
      end
    end

    context "with attached blobs" do
      let(:service) { create(:service) }
      let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

      before do
        service.images.attach(image_file)
      end

      it "does not delete attached blobs" do
        blob_id = service.images.blobs.first.id

        described_class.perform_now

        expect(ActiveStorage::Blob.exists?(blob_id)).to be true
      end
    end

    context "with recent orphaned blobs" do
      let!(:recent_orphan) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("test content"),
          filename: "recent.txt",
          content_type: "text/plain"
        )
        # Created now, not older than threshold
      end

      it "does not delete recent orphaned blobs" do
        expect {
          described_class.perform_now
        }.not_to change { ActiveStorage::Blob.exists?(recent_orphan.id) }
      end
    end

    context "in dry run mode" do
      let!(:orphaned_blob) do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("test content"),
          filename: "orphaned.txt",
          content_type: "text/plain"
        )
        blob.update_column(:created_at, 2.days.ago)
        blob
      end

      it "does not delete blobs" do
        expect {
          described_class.perform_now(dry_run: true)
        }.not_to change { ActiveStorage::Blob.exists?(orphaned_blob.id) }
      end

      it "reports what would be deleted" do
        stats = described_class.perform_now(dry_run: true)

        expect(stats[:orphaned_blobs_found]).to be >= 1
        expect(stats[:orphaned_blobs_deleted]).to eq(0)
      end
    end

    context "with verbose mode" do
      it "logs detailed information" do
        expect(Rails.logger).to receive(:info).at_least(:once).with(/OrphanedBlobCleanupJob/)

        described_class.perform_now(verbose: true)
      end
    end

    context "with errors during cleanup" do
      let!(:orphaned_blob) do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("test content"),
          filename: "orphaned.txt",
          content_type: "text/plain"
        )
        blob.update_column(:created_at, 2.days.ago)
        blob
      end

      it "continues processing after an error" do
        allow_any_instance_of(ActiveStorage::Blob).to receive(:purge).and_raise(StandardError.new("Test error"))

        stats = described_class.perform_now

        expect(stats[:errors]).not_to be_empty
        expect(stats[:errors].first[:error]).to eq("Test error")
      end
    end
  end

  describe "queue configuration" do
    it "uses the maintenance queue" do
      expect(described_class.new.queue_name).to eq("maintenance")
    end
  end

  describe "thresholds" do
    it "has a 24-hour orphan age threshold" do
      expect(described_class::ORPHAN_AGE_THRESHOLD).to eq(24.hours)
    end

    it "has a batch size limit" do
      expect(described_class::BATCH_SIZE).to eq(1000)
    end

    it "has a 48-hour variant age threshold" do
      expect(described_class::VARIANT_AGE_THRESHOLD).to eq(48.hours)
    end
  end
end
