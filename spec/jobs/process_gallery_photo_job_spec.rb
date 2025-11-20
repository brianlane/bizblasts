# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessGalleryPhotoJob, type: :job do
  let(:business) { create(:business) }
  let(:gallery_photo) { create(:gallery_photo, business: business, photo_source: :gallery) }

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
      expect(Rails.logger).to receive(:info).with(/Generated variants/)

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
    end

    it 'generates image variants' do
      # Spy on variant generation
      allow_any_instance_of(ActiveStorage::Attached::One).to receive(:variant).and_call_original

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)

      # Verify variants were requested
      expect(gallery_photo.image).to have_received(:variant).at_least(:once)
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
        # Stub HEIC support check
        allow_any_instance_of(ProcessGalleryPhotoJob).to receive(:heic_supported?).and_return(true)

        # Stub ImageProcessing
        fake_converted_file = Tempfile.new(['converted', '.jpg'])
        fake_converted_file.write('converted jpeg content')
        fake_converted_file.rewind

        allow(ImageProcessing::MiniMagick).to receive_message_chain(:source, :auto_orient, :strip, :colorspace, :saver, :convert, :call).and_return(fake_converted_file.path)

        expect(Rails.logger).to receive(:info).with(/Converting HEIC/)

        ProcessGalleryPhotoJob.perform_now(gallery_photo.id)

        fake_converted_file.close
        fake_converted_file.unlink
      end
    end

    context 'when gallery photo not found' do
      it 'logs error and does not raise' do
        expect(Rails.logger).to receive(:error).with(/not found/)

        expect {
          ProcessGalleryPhotoJob.perform_now(99999)
        }.not_to raise_error
      end
    end

    context 'when image processing fails' do
      before do
        # Simulate processing failure
        allow_any_instance_of(ActiveStorage::Attached::One).to receive(:variant).and_raise(StandardError.new('Processing failed'))
      end

      it 'logs error and does not raise' do
        expect(Rails.logger).to receive(:error).with(/Failed to process gallery photo/)

        expect {
          ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
        }.not_to raise_error
      end
    end
  end

  describe 'variant generation' do
    before do
      gallery_photo.image.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')),
        filename: 'test.jpg',
        content_type: 'image/jpeg'
      )
    end

    it 'generates large variant for lightbox' do
      expect_any_instance_of(ActiveStorage::Attached::One).to receive(:variant)
        .with(hash_including(resize_to_limit: [1920, 1920]))
        .and_call_original

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
    end

    it 'generates medium variant for gallery grid' do
      expect_any_instance_of(ActiveStorage::Attached::One).to receive(:variant)
        .with(hash_including(resize_to_limit: [800, 800]))
        .and_call_original

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
    end

    it 'generates small variant for thumbnails' do
      expect_any_instance_of(ActiveStorage::Attached::One).to receive(:variant)
        .with(hash_including(resize_to_limit: [400, 400]))
        .and_call_original

      ProcessGalleryPhotoJob.perform_now(gallery_photo.id)
    end
  end
end
