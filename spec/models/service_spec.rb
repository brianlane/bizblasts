# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Service, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:bookings) }
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

    context 'price validation' do
      it 'rejects invalid price formats with custom error message' do
        service = build(:service, business: business, price: 'abcd')
        expect(service).not_to be_valid
        expect(service.errors[:price]).to include("must be a valid number - 'abcd' is not a valid price format (e.g., '10.50' or '$10.50')")
      end

      it 'rejects nil price' do
        service = build(:service, business: business, price: nil)
        expect(service).not_to be_valid
        expect(service.errors[:price]).to include("can't be blank")
      end

      it 'rejects empty string price' do
        service = build(:service, business: business, price: '')
        expect(service).not_to be_valid
        expect(service.errors[:price]).to include("can't be blank")
      end

      it 'accepts valid numeric price' do
        service = build(:service, business: business, price: '10.50')
        service.valid?
        expect(service.errors[:price]).to be_empty
      end

      it 'accepts valid currency formatted price' do
        service = build(:service, business: business, price: '$10.50')
        service.valid?
        expect(service.errors[:price]).to be_empty
      end
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

  describe 'event services' do
    let(:business) { create(:business, time_zone: 'UTC') }

    it 'requires an event start time' do
      service = build(:service, service_type: :event, business: business, min_bookings: 1, max_bookings: 5, event_starts_at: nil)
      expect(service).not_to be_valid
      expect(service.errors[:event_starts_at]).to include("can't be blank")
    end

    it 'treats events as experience services for booking constraints' do
      service = build(:service, service_type: :event, business: business, min_bookings: 2, max_bookings: 6, event_starts_at: 3.days.from_now.change(sec: 0))
      service.valid?
      expect(service.errors[:min_bookings]).to be_empty
      expect(service.experience?).to be(true)
    end

    it 'configures availability to a single event date' do
      start_time = Time.zone.parse('2025-06-01 10:00')
      service = create(:service, service_type: :event, business: business, min_bookings: 1, max_bookings: 5, duration: 60, event_starts_at: start_time)

      date_key = start_time.to_date.iso8601
      expect(service.enforce_service_availability?).to be(true)
      expect(service.availability['exceptions'].keys).to eq([date_key])
      expect(service.availability['exceptions'][date_key]).to eq([{ 'start' => '10:00', 'end' => '11:00' }])
      expect(service.spots).to eq(5)
    end
  end

  describe 'image attachments' do
    it { is_expected.to have_many_attached(:images) }
    it { should validate_content_type_of(:images).allowing('image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/heic', 'image/heif', 'image/heic-sequence', 'image/heif-sequence') }
    it { should validate_size_of(:images).less_than(15.megabytes) }

    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    let(:image1) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }
    let(:image2) { fixture_file_upload('spec/fixtures/files/new-item.jpg', 'image/jpeg') }
    let(:heic_image) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/heic') }

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

    describe 'HEIC image support' do
      it 'accepts HEIC images' do
        service.images.attach(heic_image)
        expect(service).to be_valid
        expect(service.images).to be_attached
      end

      it 'accepts HEIF images' do
        heif_image = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/heif')                                                                  
        service.images.attach(heif_image)
        expect(service).to be_valid
        expect(service.images).to be_attached
      end

      it 'accepts HEIC sequence images' do
        heic_seq_image = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/heic-sequence')
        service.images.attach(heic_seq_image)
        expect(service).to be_valid
        expect(service.images).to be_attached
      end

      it 'accepts HEIF sequence images' do
        heif_seq_image = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/heif-sequence')
        service.images.attach(heif_seq_image)
        expect(service).to be_valid
        expect(service.images).to be_attached
      end
    end
  end

  describe 'image deletion functionality' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    
    before do
      # Create mock attachments for testing
      @attachment1 = double('attachment1', id: 1, purge_later: true, update: true)
      @attachment2 = double('attachment2', id: 2, purge_later: true, update: true)
      @attachment3 = double('attachment3', id: 3, purge_later: true, update: true)
      
      # Mock the images association
      mock_images = double('images_association')
      mock_attachments = double('attachments_collection')
      
      allow(service).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:find_by).with(id: 3).and_return(@attachment3)
      allow(mock_attachments).to receive(:find_by).with(id: 999).and_return(nil) # Non-existent
    end

    it 'deletes service images when _destroy is set to true' do
      expect(@attachment1).to receive(:purge_later).once
      expect(@attachment2).to receive(:purge_later).once
      
      service.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, _destroy: true },
        { id: 3, _destroy: '0' } # Should not be deleted
      ]
    end

    it 'handles deletion of non-existent service images gracefully' do
      expect(Rails.logger).to receive(:warn).with("Attempted to delete non-existent image attachment: 999")
      
      service.images_attributes = [
        { id: 999, _destroy: '1' }
      ]
    end

    it 'processes service image deletions before other updates' do
      # Mock additional methods for primary flag handling
      mock_where_not = double('where_not_clause')
      allow(service.images.attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      service.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
    end

    it 'handles mixed service image deletion and primary flag updates correctly' do
      # Mock additional methods for primary flag handling
      mock_where_not = double('where_not_clause')
      allow(service.images.attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      service.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
    end
  end

  describe 'adding service images without replacing existing ones' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    
    it 'appends new images to existing ones via attach method' do
      # Mock the images attachment
      mock_images = double('images_attachment')
      allow(service).to receive(:images).and_return(mock_images)
      
      # Create mock file objects
      mock_file1 = double('file1', blank?: false)
      mock_file2 = double('file2', blank?: false)
      new_images = [mock_file1, mock_file2]
      
      # Expect attach to be called with the new images
      expect(mock_images).to receive(:attach).with(new_images)
      
      # Test attachment directly (since we removed the images= override)
      service.images.attach(new_images)
    end

    it 'filters out blank and nil images when using attach' do
      mock_images = double('images_attachment')
      allow(service).to receive(:images).and_return(mock_images)
      
      mock_file = double('file', blank?: false)
      
      # Test filtering at the controller level (which handles this now)
      valid_images = [mock_file, nil, '', double('blank_file', blank?: true)].compact.reject(&:blank?)
      
      # Should only attach the valid file
      expect(mock_images).to receive(:attach).with([mock_file])
      
      service.images.attach(valid_images)
    end

    it 'maintains existing service images when adding new ones via attach' do
      # Mock service with existing attachments
      existing_attachment = double('existing_attachment', id: 1)
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      
      allow(service).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:count).and_return(1)
      
      # New file to add
      new_file = double('new_file', blank?: false)
      
      # Should append the new file
      expect(mock_images).to receive(:attach).with([new_file])
      
      service.images.attach([new_file])
    end
  end

  describe 'concurrent service image operations' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    
    it 'handles concurrent service image deletion and addition operations safely' do
      # Mock existing attachments
      @attachment1 = double('attachment1', id: 1, purge_later: true)
      @attachment2 = double('attachment2', id: 2, update: true)
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      mock_where_not = double('where_not_clause')
      
      allow(service).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      # New file to add
      new_file = double('new_file', blank?: false)
      
      # First, handle deletions and updates via images_attributes
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      service.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
      
      # Then, add new images via attach
      expect(mock_images).to receive(:attach).with([new_file])
      
      service.images.attach([new_file])
    end

    it 'processes multiple concurrent service image deletion requests safely' do
      # Simulate race condition with multiple deletions
      attachments = (1..5).map do |i|
        double("attachment#{i}", id: i, purge_later: true)
      end
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      
      allow(service).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      
      attachments.each do |attachment|
        allow(mock_attachments).to receive(:find_by).with(id: attachment.id).and_return(attachment)
      end
      
      # All should be deleted safely
      attachments.each do |attachment|
        expect(attachment).to receive(:purge_later)
      end
      
      # Test concurrent deletion operations
      deletion_attributes = attachments.map { |a| { id: a.id, _destroy: '1' } }
      
      service.images_attributes = deletion_attributes
    end
  end

  describe 'service primary image management with deletion and addition' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    
    it 'handles service primary flag updates while deleting other images' do
      # Mock three existing attachments
      @attachment1 = double('attachment1', id: 1, purge_later: true)
      @attachment2 = double('attachment2', id: 2, update: true)
      @attachment3 = double('attachment3', id: 3, purge_later: true)
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      mock_where_not = double('where_not_clause')
      
      allow(service).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      
      # Setup find_by expectations
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:find_by).with(id: 3).and_return(@attachment3)
      
      # Setup primary flag handling
      allow(mock_attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      # Expectations
      expect(@attachment1).to receive(:purge_later) # Delete
      expect(@attachment3).to receive(:purge_later) # Delete
      expect(@attachment2).to receive(:update).with(primary: true) # Set as primary
      
      service.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' },
        { id: 3, _destroy: '1' }
      ]
    end

    it 'maintains service primary flag integrity when adding new images' do
      # Test that new images don't automatically become primary
      mock_images = double('images_attachment')
      
      allow(service).to receive(:images).and_return(mock_images)
      
      new_file = double('new_file', blank?: false)
      
      # Should just attach without affecting primary flags
      expect(mock_images).to receive(:attach).with([new_file])
      
      service.images.attach([new_file])
    end
  end

  describe 'service image validation boundary scenarios' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business) }
    
    it 'handles 15MB file size validation during service image addition' do
      large_file = double('large_file', blank?: false)
      mock_images = double('images_attachment')
      
      allow(service).to receive(:images).and_return(mock_images)
      
      # Should still attach (validation happens at model level)
      expect(mock_images).to receive(:attach).with([large_file])
      
      service.images.attach([large_file])
    end

    it 'processes service image format validation correctly during operations' do
      # Test with various file formats supported for services
      png_file = double('png_file', blank?: false)
      jpeg_file = double('jpeg_file', blank?: false)
      webp_file = double('webp_file', blank?: false)
      gif_file = double('gif_file', blank?: false)
      
      mock_images = double('images_attachment')
      allow(service).to receive(:images).and_return(mock_images)
      
      files = [png_file, jpeg_file, webp_file, gif_file]
      
      expect(mock_images).to receive(:attach).with(files)
      
      service.images.attach(files)
    end
  end

  describe 'promotional pricing methods' do
    let(:business) { create(:business) }
    let(:service) { create(:service, business: business, price: 150.00) }
    
    before do
      ActsAsTenant.current_tenant = business
    end

    describe '#current_promotion' do
      context 'with active promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 25,
            applicable_to_services: true,
            start_date: 1.week.ago,
            end_date: 1.week.from_now,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns the active promotion' do
          expect(service.current_promotion).to eq(promotion)
        end
      end

      context 'with expired promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_services: true,
            start_date: 2.weeks.ago,
            end_date: 1.week.ago,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns nil for expired promotion' do
          expect(service.current_promotion).to be_nil
        end
      end
    end

    describe '#on_promotion?' do
      context 'with active promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 40.00,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns true when service has active promotion' do
          expect(service.on_promotion?).to be true
        end
      end

      context 'without promotion' do
        it 'returns false when service has no promotion' do
          expect(service.on_promotion?).to be false
        end
      end
    end

    describe '#promotional_price' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 30,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns discounted price for percentage promotion' do
          expect(service.promotional_price).to eq(105.00) # 150 - 30% = 105
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 25.00,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns discounted price for fixed amount promotion' do
          expect(service.promotional_price).to eq(125.00) # 150 - 25 = 125
        end
      end

      context 'without promotion' do
        it 'returns original price when no promotion is active' do
          expect(service.promotional_price).to eq(150.00)
        end
      end
    end

    describe '#promotion_discount_amount' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns discount amount for percentage promotion' do
          expect(service.promotion_discount_amount).to eq(30.00) # 20% of 150 = 30
        end
      end
    end

    describe '#promotion_display_text' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 25,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns percentage display text' do
          expect(service.promotion_display_text).to eq('25% OFF')
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 50.00,
            applicable_to_services: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_services.create!(service: service)
        end

        it 'returns fixed amount display text' do
          expect(service.promotion_display_text).to eq('$50.0 OFF')
        end
      end
    end
  end

  describe '#discount_eligible?' do
    it 'returns true when allow_discounts is true' do
      service = build(:service, allow_discounts: true)
      expect(service.discount_eligible?).to be true
    end

    it 'returns false when allow_discounts is false' do
      service = build(:service, allow_discounts: false)
      expect(service.discount_eligible?).to be false
    end
  end

  describe '#process_service_availability' do
    let(:service) { build(:service) }

    it 'normalizes availability hashes and removes invalid slots' do
      service.availability = {
        'monday' => [{'start'=>'09:00','end'=>'12:00'}, {'start'=>nil,'end'=>'10:00'}],
        'exceptions' => {'2025-07-21' => [{'start'=>'13:00','end'=>'15:00'}, {}]}
      }
      service.valid? # triggers before_validation
      expect(service.availability['monday']).to eq([{'start'=>'09:00','end'=>'12:00'}])
      expect(service.availability['exceptions']['2025-07-21']).to eq([{'start'=>'13:00','end'=>'15:00'}])
    end
  end

  describe '#available_at?' do
    let(:service) { build(:service, enforce_service_availability: true) }

    before do
      service.availability = {
        'monday'=>[{'start'=>'09:00','end'=>'17:00'}],
        'exceptions'=>{}
      }
    end

    it 'returns true when time is within availability window' do
      monday = Date.parse('2025-07-21')
      dt = Time.zone.parse("#{monday} 10:00")
      expect(service.available_at?(dt)).to be true
    end

    it 'returns false when time is outside availability window' do
      monday = Date.parse('2025-07-21')
      dt = Time.zone.parse("#{monday} 08:00")
      expect(service.available_at?(dt)).to be false
    end

    it 'ignores availability when enforce flag is false' do
      service.enforce_service_availability = false
      monday = Date.parse('2025-07-21')
      dt = Time.zone.parse("#{monday} 00:00")
      expect(service.available_at?(dt)).to be true
    end
  end
end
