# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GalleryPhoto, type: :model do
  let(:business) { create(:business) }
  subject(:gallery_photo) { create(:gallery_photo, business: business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:source).optional }
    it { is_expected.to have_one_attached(:image) }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:photo_source)
        .with_values(gallery: 0, service: 1, product: 2)
        .with_prefix(:photo_source)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than(0) }
    it { is_expected.to validate_presence_of(:photo_source) }

    context 'max photos per business' do
      before do
        create_list(:gallery_photo, 100, business: business)
      end

      it 'does not allow more than 100 photos' do
        photo = build(:gallery_photo, business: business)
        expect(photo).not_to be_valid
        expect(photo.errors[:base]).to include('Maximum 100 photos allowed per gallery')
      end
    end

    context 'max featured photos' do
      before do
        create_list(:gallery_photo, 5, business: business, featured: true)
      end

      it 'does not allow more than 5 featured photos' do
        photo = build(:gallery_photo, business: business, featured: true)
        expect(photo).not_to be_valid
        expect(photo.errors[:featured]).to include('Maximum 5 photos can be featured')
      end
    end

    context 'photo source validation' do
      it 'requires attached image for gallery photos' do
        photo = build(:gallery_photo, business: business, photo_source: :gallery)
        photo.image.purge if photo.image.attached?
        expect(photo).not_to be_valid
        expect(photo.errors[:image]).to include('must be attached for gallery photos')
      end

      it 'requires source_attachment_id for service photos' do
        photo = build(:gallery_photo, business: business, photo_source: :service, source_attachment_id: nil)
        expect(photo).not_to be_valid
        expect(photo.errors[:source_attachment_id]).to include('must be present for service/product photos')
      end
    end

    context 'image attachment validation' do
      it 'rejects files larger than 15MB' do
        photo = build(:gallery_photo, business: business, photo_source: :gallery)
        # Stub the byte_size to simulate a large file
        allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(16.megabytes)
        photo.image.attach(
          io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test-image.jpg')),
          filename: 'large.jpg',
          content_type: 'image/jpeg'
        )

        expect(photo).not_to be_valid
        expect(photo.errors[:image]).to include('size must be less than 15MB')
      end

      it 'rejects invalid file formats' do
        photo = build(:gallery_photo, business: business, photo_source: :gallery)
        photo.image.attach(
          io: StringIO.new('test content'),
          filename: 'test.pdf',
          content_type: 'application/pdf'
        )

        expect(photo).not_to be_valid
        expect(photo.errors[:image]).to include('must be a JPEG, PNG, GIF, WebP, or HEIC file')
      end
    end
  end

  describe 'scopes' do
    let!(:featured_photo1) { create(:gallery_photo, business: business, featured: true, position: 1) }
    let!(:featured_photo2) { create(:gallery_photo, business: business, featured: true, position: 2) }
    let!(:regular_photo) { create(:gallery_photo, business: business, featured: false, position: 3) }
    let!(:hero_photo) { create(:gallery_photo, business: business, display_in_hero: true, position: 4) }

    describe '.featured' do
      it 'returns only featured photos ordered by position' do
        expect(business.gallery_photos.featured).to eq([featured_photo1, featured_photo2])
      end
    end

    describe '.not_featured' do
      it 'returns only non-featured photos' do
        expect(business.gallery_photos.not_featured.pluck(:id)).to include(regular_photo.id)
        expect(business.gallery_photos.not_featured.pluck(:id)).not_to include(featured_photo1.id)
      end
    end

    describe '.hero_display' do
      it 'returns photos marked for hero display' do
        expect(business.gallery_photos.hero_display).to eq([hero_photo])
      end
    end

    describe '.gallery_uploads' do
      let!(:gallery_upload) { create(:gallery_photo, business: business, photo_source: :gallery) }

      it 'returns only gallery-uploaded photos' do
        expect(business.gallery_photos.gallery_uploads).to include(gallery_upload)
      end
    end
  end

  describe 'callbacks' do
    describe 'set_next_position' do
      it 'automatically sets position for new photos' do
        photo1 = create(:gallery_photo, business: business)
        photo2 = build(:gallery_photo, business: business)

        photo2.save!
        expect(photo2.position).to eq(photo1.position + 1)
      end
    end

    describe 'reorder_positions after destroy' do
      let!(:photo1) { create(:gallery_photo, business: business, position: 1) }
      let!(:photo2) { create(:gallery_photo, business: business, position: 2) }
      let!(:photo3) { create(:gallery_photo, business: business, position: 3) }

      it 'reorders positions after deletion' do
        photo2.destroy

        photo1.reload
        photo3.reload

        expect(photo1.position).to eq(1)
        expect(photo3.position).to eq(2)
      end
    end
  end

  describe '#image_url' do
    context 'for gallery photos' do
      it 'returns URL for the specified variant' do
        photo = create(:gallery_photo, business: business, photo_source: :gallery)
        expect(photo.image_url(:medium)).to be_present
      end
    end

    context 'for service/product photos' do
      let(:service) { create(:service, business: business) }
      let(:attachment) do
        File.open(Rails.root.join('spec/fixtures/files/test-image.jpg')) do |file|
          service.images.attach(
            io: file,
            filename: 'service-photo.jpg',
            content_type: 'image/jpeg'
          )
        end
        service.images.attachments.first
      end

      it 'fetches URL from source attachment' do
        photo = create(:gallery_photo,
          business: business,
          photo_source: :service,
          source: service,
          source_attachment_id: attachment.id
        )

        expect(photo.image_url(:medium)).to be_present
      end
    end
  end

  describe '#reorder' do
    let!(:photo1) { create(:gallery_photo, business: business, position: 1) }
    let!(:photo2) { create(:gallery_photo, business: business, position: 2) }
    let!(:photo3) { create(:gallery_photo, business: business, position: 3) }

    it 'moves photo down and shifts others up' do
      photo1.reorder(3)

      photo1.reload
      photo2.reload
      photo3.reload

      expect(photo1.position).to eq(3)
      expect(photo2.position).to eq(1)
      expect(photo3.position).to eq(2)
    end

    it 'moves photo up and shifts others down' do
      photo3.reorder(1)

      photo1.reload
      photo2.reload
      photo3.reload

      expect(photo3.position).to eq(1)
      expect(photo1.position).to eq(2)
      expect(photo2.position).to eq(3)
    end
  end

  describe '#toggle_featured!' do
    let(:photo) { create(:gallery_photo, business: business, featured: false) }

    it 'toggles featured status to true' do
      expect { photo.toggle_featured! }.to change { photo.featured }.from(false).to(true)
    end

    it 'toggles featured status to false' do
      photo.update!(featured: true)
      expect { photo.toggle_featured! }.to change { photo.featured }.from(true).to(false)
    end

    context 'when 5 photos are already featured' do
      before do
        create_list(:gallery_photo, 5, business: business, featured: true)
      end

      it 'does not allow featuring another photo' do
        result = photo.toggle_featured!
        expect(result).to be false
        expect(photo.errors[:featured]).to include('Maximum 5 photos can be featured')
      end
    end
  end
end
