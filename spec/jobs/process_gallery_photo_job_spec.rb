# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessGalleryPhotoJob, type: :job do
  let(:business) { create(:business) }
  let(:gallery_photo) { create(:gallery_photo, business: business, photo_source: :gallery) }
  let(:logger) { Rails.logger }

  describe 'queue configuration' do
    it 'uses the image_processing queue' do
      expect(described_class.new.queue_name).to eq('image_processing')
    end
  end

  describe 'MAX_PROCESSABLE_SIZE' do
    it 'is set to 10 megabytes' do
      expect(described_class::MAX_PROCESSABLE_SIZE).to eq(10.megabytes)
    end
  end

  describe '#perform' do
    before do
      # Attach a test image
      gallery_photo.image.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')),
        filename: 'test.jpg',
        content_type: 'image/jpeg'
      )
    end

    it 'processes the image successfully' do
      allow(logger).to receive(:info).and_call_original

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)

      expect(logger).to have_received(:info).with(/Generated 3 variants for gallery photo/)
    end

    context 'when file exceeds MAX_PROCESSABLE_SIZE' do
      before do
        # Mock the blob size to exceed the limit by stubbing on any instance
        allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(15.megabytes)
      end

      it 'skips variant generation and logs a warning' do
        allow(logger).to receive(:warn).and_call_original

        ProcessGalleryPhotoJob.perform_now(gallery_photo.id)

        expect(logger).to have_received(:warn).with(/Skipping variant generation for large file/)
      end
    end

    context 'with HEIC image' do
      before do
        gallery_photo.image.purge
        gallery_photo.image.attach(
          io: StringIO.new('fake heic content'),
          filename: 'test.heic',
          content_type: 'image/heic'
        )
      end

      it 'converts HEIC to JPEG' do
        allow_any_instance_of(ProcessGalleryPhotoJob).to receive(:heic_supported?).and_return(true)
        allow(logger).to receive(:info).and_call_original

        expect_any_instance_of(ProcessGalleryPhotoJob).to receive(:convert_heic_to_jpeg).and_call_original

        ProcessGalleryPhotoJob.perform_now(gallery_photo.id)

        expect(logger).to have_received(:info).with(/Converting HEIC/)
      end
    end

    context 'when gallery photo not found' do
      it 'logs error and does not raise' do
        allow(logger).to receive(:error).and_call_original

        expect {
          ProcessGalleryPhotoJob.perform_now(99999)
        }.not_to raise_error

        expect(logger).to have_received(:error).with(/not found/)
      end
    end

    context 'when image processing fails' do
      it 'logs error and does not raise' do
        allow(logger).to receive(:error).and_call_original
        allow_any_instance_of(ProcessGalleryPhotoJob).to receive(:generate_variants).and_raise(StandardError.new('Processing failed'))

        expect {
          ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
        }.not_to raise_error

        expect(logger).to have_received(:error).with(/Failed to process gallery photo/)
      end
    end
  end

  describe 'variant generation' do
    before do
      gallery_photo.image.purge
      gallery_photo.image.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')),
        filename: 'test.jpg',
        content_type: 'image/jpeg'
      )
    end

    it 'creates three tracked variants for the blob' do
      expect {
        ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
      }.to change {
        ActiveStorage::VariantRecord.where(blob: gallery_photo.image.blob).count
      }.by(3)
    end
  end
end
