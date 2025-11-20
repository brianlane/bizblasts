# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GalleryVideoService do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#upload' do
    let(:video_file) { fixture_file_upload('test-video.mp4', 'video/mp4') }
    let(:params) do
      {
        title: 'My Video',
        display_location: 'hero',
        autoplay_hero: true
      }
    end

    it 'attaches video and updates business attributes' do
      service.upload(video_file, params)

      business.reload
      expect(business.gallery_video).to be_attached
      expect(business.video_title).to eq('My Video')
      expect(business.video_display_location).to eq('hero')
      expect(business.video_autoplay_hero).to be true
    end

    context 'with invalid file format' do
      let(:invalid_file) { fixture_file_upload('test-image.jpg', 'image/jpeg') }

      it 'raises VideoValidationError' do
        expect {
          service.upload(invalid_file, params)
        }.to raise_error(GalleryVideoService::VideoValidationError, /Unsupported video format/)
      end
    end

    context 'with file exceeding size limit' do
      let(:large_file) { fixture_file_upload('test-video.mp4', 'video/mp4') }

      before do
        # Stub the file size
        allow(large_file).to receive(:size).and_return(51.megabytes)
      end

      it 'raises VideoValidationError' do
        expect {
          service.upload(large_file, params)
        }.to raise_error(GalleryVideoService::VideoValidationError, /exceeds maximum/)
      end
    end
  end

  describe '#update_display_settings' do
    before do
      video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
      business.gallery_video.attach(video_file)
      business.save!
    end

    it 'updates video display settings' do
      service.update_display_settings(
        title: 'Updated Title',
        display_location: 'gallery',
        autoplay_hero: false
      )

      business.reload
      expect(business.video_title).to eq('Updated Title')
      expect(business.video_display_location).to eq('gallery')
      expect(business.video_autoplay_hero).to be false
    end

    it 'raises error if no video is attached' do
      business.gallery_video.purge
      business.reload

      expect {
        service.update_display_settings(title: 'Test')
      }.to raise_error(GalleryVideoService::VideoNotFoundError)
    end
  end

  describe '#remove' do
    before do
      video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
      business.gallery_video.attach(video_file)
      business.update!(video_title: 'My Video')
    end

    it 'removes video and clears related attributes' do
      service.remove

      business.reload
      expect(business.gallery_video).not_to be_attached
      expect(business.video_title).to be_nil
      expect(business.video_display_location).to eq('hero') # default value
    end
  end

  describe '#video_info' do
    context 'when video is attached' do
      before do
        video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
        business.gallery_video.attach(video_file)
        business.save!
      end

      it 'returns video information' do
        info = service.video_info

        expect(info).to include(:filename, :content_type, :size_mb, :url)
        expect(info[:content_type]).to eq('video/mp4')
        expect(info[:size_mb]).to be > 0
      end
    end

    context 'when no video is attached' do
      it 'returns nil' do
        expect(service.video_info).to be_nil
      end
    end
  end

  describe '#thumbnail_url' do
    before do
      video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
      business.gallery_video.attach(video_file)
      business.save!
    end

    it 'returns the video URL as thumbnail' do
      url = service.thumbnail_url
      expect(url).to be_present
      expect(url).to include('test-video.mp4')
    end
  end

  describe 'private#validate_video_format!' do
    it 'accepts MP4 format' do
      file = double('file', content_type: 'video/mp4')
      expect { service.send(:validate_video_format!, file) }.not_to raise_error
    end

    it 'accepts WebM format' do
      file = double('file', content_type: 'video/webm')
      expect { service.send(:validate_video_format!, file) }.not_to raise_error
    end

    it 'accepts QuickTime format' do
      file = double('file', content_type: 'video/quicktime')
      expect { service.send(:validate_video_format!, file) }.not_to raise_error
    end

    it 'accepts AVI format' do
      file = double('file', content_type: 'video/x-msvideo')
      expect { service.send(:validate_video_format!, file) }.not_to raise_error
    end

    it 'rejects invalid format' do
      file = double('file', content_type: 'application/pdf')
      expect {
        service.send(:validate_video_format!, file)
      }.to raise_error(GalleryVideoService::VideoValidationError)
    end
  end

  describe 'private#validate_video_size!' do
    it 'accepts file within size limit' do
      file = double('file', size: 30.megabytes)
      expect { service.send(:validate_video_size!, file) }.not_to raise_error
    end

    it 'rejects file exceeding size limit' do
      file = double('file', size: 60.megabytes)
      expect {
        service.send(:validate_video_size!, file)
      }.to raise_error(GalleryVideoService::VideoValidationError, /exceeds maximum/)
    end
  end
end
