# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessGalleryVideoJob, type: :job do
  let(:business) { create(:business) }

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
      expect(Rails.logger).to receive(:info).with(/Successfully processed video/)

      ProcessGalleryVideoJob.perform_now(business.id)
    end

    it 'logs video information' do
      expect(Rails.logger).to receive(:info).with(/Processing video for business/)

      ProcessGalleryVideoJob.perform_now(business.id)
    end

    context 'when business not found' do
      it 'logs error and does not raise' do
        expect(Rails.logger).to receive(:error).with(/Business .* not found/)

        expect {
          ProcessGalleryVideoJob.perform_now(99999)
        }.not_to raise_error
      end
    end

    context 'when no video is attached' do
      before do
        business.gallery_video.purge
      end

      it 'returns early without processing' do
        expect(Rails.logger).not_to receive(:info).with(/Successfully processed/)

        ProcessGalleryVideoJob.perform_now(business.id)
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

      it 'logs validation error and removes invalid video' do
        expect(Rails.logger).to receive(:error).with(/Video validation failed/)
        expect(Rails.logger).to receive(:error).with(/Invalid video for business/)

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

      it 'logs validation error and removes invalid video' do
        expect(Rails.logger).to receive(:error).with(/Video validation failed.*exceeds maximum/)
        expect(Rails.logger).to receive(:error).with(/Invalid video for business/)

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
        expect(Rails.logger).to receive(:error).with(/Failed to process gallery video/)
        expect(Rails.logger).to receive(:error)

        expect {
          ProcessGalleryVideoJob.perform_now(business.id)
        }.not_to raise_error
      end
    end
  end
end
