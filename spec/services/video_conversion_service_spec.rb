# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoConversionService do
  let(:business) { create(:business) }

  describe '.needs_conversion?' do
    it 'returns true for QuickTime videos' do
      blob = instance_double(ActiveStorage::Blob, content_type: 'video/quicktime')
      expect(described_class.needs_conversion?(blob)).to be true
    end

    it 'returns true for AVI videos' do
      blob = instance_double(ActiveStorage::Blob, content_type: 'video/x-msvideo')
      expect(described_class.needs_conversion?(blob)).to be true
    end

    it 'returns false for MP4 videos' do
      blob = instance_double(ActiveStorage::Blob, content_type: 'video/mp4')
      expect(described_class.needs_conversion?(blob)).to be false
    end

    it 'returns false for WebM videos' do
      blob = instance_double(ActiveStorage::Blob, content_type: 'video/webm')
      expect(described_class.needs_conversion?(blob)).to be false
    end

    it 'returns false for nil blob' do
      expect(described_class.needs_conversion?(nil)).to be false
    end
  end

  describe '.ffmpeg_available?' do
    it 'returns a boolean indicating ffmpeg availability' do
      result = described_class.ffmpeg_available?
      expect([true, false]).to include(result)
    end
  end

  describe '.convert!' do
    context 'when no video is attached' do
      it 'returns false' do
        expect(described_class.convert!(business)).to be false
      end
    end

    context 'when video is already MP4' do
      let(:video_file) do
        fixture_file_upload(
          Rails.root.join('spec/fixtures/files/test_video.mp4'),
          'video/mp4'
        )
      end

      before do
        # Skip if test video doesn't exist
        skip 'Test video not available' unless File.exist?(Rails.root.join('spec/fixtures/files/test_video.mp4'))
        business.gallery_video.attach(video_file)
      end

      it 'returns true without converting' do
        expect(described_class.convert!(business)).to be true
      end
    end

    context 'when video needs conversion but ffmpeg is not available' do
      before do
        allow(described_class).to receive(:ffmpeg_available?).and_return(false)

        # Attach a QuickTime video
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.mov',
          content_type: 'video/quicktime'
        )
      end

      it 'returns false' do
        expect(described_class.convert!(business)).to be false
      end
    end

    context 'when original_blob_id is provided but video has changed' do
      before do
        business.gallery_video.attach(
          io: StringIO.new('fake video content'),
          filename: 'test.mov',
          content_type: 'video/quicktime'
        )
      end

      it 'returns false if current blob ID does not match' do
        original_id = business.gallery_video.blob.id
        # Provide a different blob ID to simulate video replacement
        result = described_class.convert!(business, original_blob_id: original_id + 999)
        expect(result).to be false
      end
    end
  end
end

