# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessGalleryVideoJob, type: :job do
  let(:business) { create(:business) }
  let(:logger) { spy('Logger', info: nil, error: nil, warn: nil) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe '#perform' do
    before do
      # Attach a test video
      business.gallery_video.attach(
        io: StringIO.new('fake video content'),
        filename: 'test.mp4',
        content_type: 'video/mp4'
      )
    end

    it 'processes the video successfully' do
      ProcessGalleryVideoJob.perform_now(business.id)

      expect(logger).to have_received(:info).with(/Successfully processed video/)
    end

    it 'logs video information' do
      ProcessGalleryVideoJob.perform_now(business.id)

      expect(logger).to have_received(:info).with(/Processing video for business/)
    end

    context 'when business not found' do
      it 'logs error and does not raise' do
        expect {
          ProcessGalleryVideoJob.perform_now(99999)
        }.not_to raise_error

        expect(logger).to have_received(:error).with(/Business .* not found/)
      end
    end

    context 'when no video is attached' do
      before do
        business.gallery_video.purge
      end

      it 'returns early without processing' do
        ProcessGalleryVideoJob.perform_now(business.id)

        expect(logger).not_to have_received(:info).with(/Successfully processed/)
      end
    end
  end

  describe 'video validation' do
    context 'with valid MP4 video' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.mp4',
          content_type: 'video/mp4'
        )
      end

      it 'passes validation' do
        expect {
          ProcessGalleryVideoJob.perform_now(business.id)
        }.not_to raise_error
      end
    end

    context 'with valid WebM video' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.webm',
          content_type: 'video/webm'
        )
      end

      it 'passes validation' do
        expect {
          ProcessGalleryVideoJob.perform_now(business.id)
        }.not_to raise_error
      end
    end

    context 'with invalid content type' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake content'),
          filename: 'test.pdf',
          content_type: 'application/pdf'
        )
      end

      it 'removes invalid video' do
        ProcessGalleryVideoJob.perform_now(business.id)

        business.reload
        expect(business.gallery_video).not_to be_attached
      end
    end

    context 'with file exceeding size limit' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'large.mp4',
          content_type: 'video/mp4'
        )

        # Stub byte_size to simulate large file
        allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(51.megabytes)
      end

      it 'removes invalid video' do
        ProcessGalleryVideoJob.perform_now(business.id)

        business.reload
        expect(business.gallery_video).not_to be_attached
      end
    end
  end

  describe 'thumbnail generation support check' do
    let(:job) { ProcessGalleryVideoJob.new }

    context 'when ffmpeg is available' do
      before do
        allow(job).to receive(:`).with('which ffmpeg 2>/dev/null').and_return('/usr/bin/ffmpeg')
      end

      it 'returns true' do
        expect(job.send(:thumbnail_generation_supported?)).to be true
      end
    end

    context 'when ffmpeg is not available' do
      before do
        allow(job).to receive(:`).with('which ffmpeg 2>/dev/null').and_return('')
      end

      it 'returns false' do
        expect(job.send(:thumbnail_generation_supported?)).to be false
      end
    end
  end

  describe 'video conversion' do
    context 'with MP4 video (no conversion needed)' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.mp4',
          content_type: 'video/mp4'
        )
      end

      it 'logs that video is already web-compatible' do
        ProcessGalleryVideoJob.perform_now(business.id)

        expect(logger).to have_received(:info).with(/already in web-compatible format/)
      end
    end

    context 'with MOV video (conversion needed)' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.mov',
          content_type: 'video/quicktime'
        )
      end

      it 'logs that video needs conversion' do
        allow(VideoConversionService).to receive(:convert!).and_return(false)

        ProcessGalleryVideoJob.perform_now(business.id)

        expect(logger).to have_received(:info).with(/needs conversion to MP4/)
      end

      it 'calls VideoConversionService.convert!' do
        blob_id = business.gallery_video.blob.id
        expect(VideoConversionService).to receive(:convert!).with(business, original_blob_id: blob_id).and_return(false)

        ProcessGalleryVideoJob.perform_now(business.id)
      end
    end
  end

  describe 'error handling' do
    before do
      business.gallery_video.attach(
        io: StringIO.new('fake video content'),
        filename: 'test.mp4',
        content_type: 'video/mp4'
      )
    end

    context 'when unexpected error occurs' do
      before do
        allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_raise(StandardError.new('Unexpected error'))
      end

      it 'logs the error with backtrace' do
        expect {
          ProcessGalleryVideoJob.perform_now(business.id)
        }.not_to raise_error

        expect(logger).to have_received(:error).with(/Failed to process gallery video/)
      end
    end
  end
end
