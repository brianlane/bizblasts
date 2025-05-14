# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Service, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:staff_assignments).dependent(:destroy) }
    it { is_expected.to have_many(:assigned_staff).through(:staff_assignments).source(:user) }
  end

  describe 'validations' do
    let(:business) { create(:business) }
    subject { build(:service, business: business) }
    
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:duration) }
    it { is_expected.to validate_presence_of(:price) }
    
    it 'validates uniqueness of name scoped to business_id' do
      create(:service, name: 'Test Service', business: business)
      duplicate = build(:service, name: 'Test Service', business: business)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end
    
    it 'allows duplicate names across different businesses' do
      business1 = create(:business)
      business2 = create(:business)
      create(:service, name: 'Test Service', business: business1)
      service2 = build(:service, name: 'Test Service', business: business2)
      expect(service2).to be_valid
    end
  end

  describe 'scopes' do
    it '.active returns only active services' do
      business = create(:business)
      active_service = create(:service, active: true, business: business)
      inactive_service = create(:service, active: false, business: business)
      
      expect(Service.active).to include(active_service)
      expect(Service.active).not_to include(inactive_service)
    end
  end

  describe 'validations for experience services' do
    let(:business) { create(:business) }

    it 'validates numericality of min_bookings for experience services' do
      service = build(:service, service_type: :experience, business: business, min_bookings: 0, max_bookings: 5)
      expect(service).not_to be_valid
      expect(service.errors[:min_bookings]).to include('must be greater than or equal to 1')
    end

    it 'validates numericality of max_bookings >= min_bookings' do
      service = build(:service, service_type: :experience, business: business, min_bookings: 3, max_bookings: 2)
      expect(service).not_to be_valid
      expect(service.errors[:max_bookings]).to include('must be greater than or equal to 3')
    end

    it 'validates numericality of spots >= 0' do
      service = build(:service, service_type: :experience, business: business, min_bookings: 1, max_bookings: 5, spots: -1)
      expect(service).not_to be_valid
      expect(service.errors[:spots]).to include('must be greater than or equal to 0')
    end

    it 'sets spots to max_bookings upon creation' do
      service = create(:service, service_type: :experience, business: business, min_bookings: 2, max_bookings: 4)
      expect(service.spots).to eq(4)
    end
  end

  describe 'image attachments' do
    it { is_expected.to have_many_attached(:images) }
    it { should validate_content_type_of(:images).allowing('image/png', 'image/jpeg') }
    it { should validate_size_of(:images).less_than(5.megabytes) }

    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    let(:image1) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }
    let(:image2) { fixture_file_upload('spec/fixtures/files/new-item.jpg', 'image/jpeg') }

    before do
      service.images.attach(image1, image2)
    end

    describe '#primary_image' do
      it 'returns nil when no primary image is set' do
        expect(service.primary_image).to be_nil
      end

      it 'returns the primary image when one is set' do
        service.images.first.update(primary: true)
        expect(service.primary_image).to eq(service.images.first)
      end
    end

    describe '#images.ordered' do
      it 'returns images ordered by position' do
        service.images.each_with_index do |img, index|
          img.update(position: index)
        end
        expect(service.images.ordered.map(&:id)).to eq(service.images.map(&:id))
      end
    end
  end
end
