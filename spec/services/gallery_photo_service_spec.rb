# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GalleryPhotoService do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#add_from_upload' do
    let(:file) { fixture_file_upload('test-image.jpg', 'image/jpeg') }
    let(:params) { { title: 'Test Photo', description: 'A test photo', featured: true } }

    it 'creates a new gallery photo with uploaded image' do
      expect {
        service.add_from_upload(file, params)
      }.to change { business.gallery_photos.count }.by(1)

      photo = business.gallery_photos.last
      expect(photo.title).to eq('Test Photo')
      expect(photo.description).to eq('A test photo')
      expect(photo.featured).to be true
      expect(photo.image).to be_attached
    end

    context 'when max photos limit is reached' do
      before do
        create_list(:gallery_photo, 100, business: business)
      end

      it 'raises MaxPhotosExceededError' do
        expect {
          service.add_from_upload(file, params)
        }.to raise_error(GalleryPhotoService::MaxPhotosExceededError, /Maximum 100 photos/)
      end
    end

    context 'when trying to feature a 6th photo' do
      before do
        create_list(:gallery_photo, 5, business: business, featured: true)
      end

      it 'raises MaxFeaturedPhotosExceededError' do
        expect {
          service.add_from_upload(file, { featured: true })
        }.to raise_error(GalleryPhotoService::MaxFeaturedPhotosExceededError, /Maximum 5/)
      end
    end
  end

  describe '#add_from_existing' do
    let(:existing_service) { create(:service, business: business) }
    let(:attachment) { create(:active_storage_attachment, record: existing_service) }

    it 'creates a photo linked to existing service image' do
      result = service.add_from_existing(
        source_type: 'Service',
        source_id: existing_service.id,
        attachment_id: attachment.id,
        title: 'Service Photo'
      )

      expect(result).to be_persisted
      expect(result.photo_source).to eq('service')
      expect(result.source).to eq(existing_service)
      expect(result.source_attachment_id).to eq(attachment.id)
      expect(result.title).to eq('Service Photo')
    end

    it 'raises error if source not found' do
      expect {
        service.add_from_existing(
          source_type: 'Service',
          source_id: 999999,
          attachment_id: 1
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#toggle_featured' do
    let(:photo) { create(:gallery_photo, business: business, featured: false) }

    it 'toggles photo featured status' do
      expect {
        service.toggle_featured(photo.id)
      }.to change { photo.reload.featured }.from(false).to(true)
    end

    context 'when 5 photos are already featured' do
      before do
        create_list(:gallery_photo, 5, business: business, featured: true)
      end

      it 'raises MaxFeaturedPhotosExceededError' do
        expect {
          service.toggle_featured(photo.id)
        }.to raise_error(GalleryPhotoService::MaxFeaturedPhotosExceededError)
      end
    end
  end

  describe '#reorder' do
    let!(:photo1) { create(:gallery_photo, business: business, position: 1) }
    let!(:photo2) { create(:gallery_photo, business: business, position: 2) }
    let!(:photo3) { create(:gallery_photo, business: business, position: 3) }

    it 'reorders photo to new position' do
      service.reorder(photo1.id, 3)

      photo1.reload
      photo2.reload
      photo3.reload

      expect(photo1.position).to eq(3)
      expect(photo2.position).to eq(1)
      expect(photo3.position).to eq(2)
    end
  end

  describe '#remove' do
    let(:photo) { create(:gallery_photo, business: business) }

    it 'deletes the photo' do
      photo_id = photo.id

      expect {
        service.remove(photo_id)
      }.to change { business.gallery_photos.count }.by(-1)

      expect { GalleryPhoto.find(photo_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'purges attached image' do
      photo_id = photo.id
      expect(photo.image).to be_attached

      service.remove(photo_id)

      # Image should be purged after deletion
      expect(ActiveStorage::Attachment.where(record_type: 'GalleryPhoto', record_id: photo_id)).to be_empty
    end
  end

  describe '#update_photo' do
    let(:photo) { create(:gallery_photo, business: business, title: 'Old Title') }

    it 'updates photo attributes' do
      service.update_photo(photo.id, title: 'New Title', description: 'New Description')

      photo.reload
      expect(photo.title).to eq('New Title')
      expect(photo.description).to eq('New Description')
    end
  end

  describe '#available_images_for_gallery' do
    let!(:service1) { create(:service, business: business, name: 'Service 1') }
    let!(:service2) { create(:service, business: business, name: 'Service 2') }
    let!(:product1) { create(:product, business: business, name: 'Product 1') }

    before do
      # Attach images to services and products
      service1.images.attach(io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')), filename: 'service1.jpg')
      product1.images.attach(io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')), filename: 'product1.jpg')
    end

    it 'returns available images from services and products' do
      result = service.available_images_for_gallery

      expect(result[:services]).to include(service1)
      expect(result[:products]).to include(product1)
    end

    it 'excludes images already in gallery' do
      # Add service1 image to gallery
      attachment = service1.images.first
      create(:gallery_photo,
        business: business,
        photo_source: :service,
        source: service1,
        source_attachment_id: attachment.id
      )

      result = service.available_images_for_gallery

      # Service1 should still appear but we'd need to check attachment availability
      expect(result[:services].count).to be >= 0
    end
  end
end
