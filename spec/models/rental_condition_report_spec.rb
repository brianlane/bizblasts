# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalConditionReport, type: :model do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, :rental, business: business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:booking) { create(:rental_booking, business: business, product: rental_product, tenant_customer: customer) }
  let(:staff) { create(:staff_member, business: business) }

  describe 'associations' do
    it { should belong_to(:rental_booking) }
    it { should belong_to(:staff_member).optional }

    it 'has many attached photos' do
      report = create(:rental_condition_report, rental_booking: booking, staff_member: staff)
      expect(report.photos).to be_an_instance_of(ActiveStorage::Attached::Many)
    end
  end

  describe 'validations' do
    subject { build(:rental_condition_report, rental_booking: booking, staff_member: staff) }

    it { should validate_presence_of(:report_type) }
    it { should validate_inclusion_of(:report_type).in_array(RentalConditionReport::REPORT_TYPES) }
    it { should validate_inclusion_of(:condition_rating).in_array(RentalConditionReport::CONDITION_RATINGS).allow_nil }

    it 'validates damage assessment is non-negative' do
      report = build(:rental_condition_report, rental_booking: booking, damage_assessment_amount: -10)
      expect(report).not_to be_valid
      expect(report.errors[:damage_assessment_amount]).to include('must be greater than or equal to 0')
    end
  end

  describe 'photo attachments' do
    let(:report) { create(:rental_condition_report, rental_booking: booking, staff_member: staff) }

    it 'allows attaching photos' do
      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')
      report.photos.attach(file)

      expect(report.photos).to be_attached
      expect(report.photo_count).to eq(1)
    end

    it 'allows multiple photos up to MAX_PHOTOS limit' do
      5.times do
        file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')
        report.photos.attach(file)
      end

      expect(report.photo_count).to eq(5)
      expect(report).to be_valid
    end

    it 'rejects more than MAX_PHOTOS photos' do
      (RentalConditionReport::MAX_PHOTOS + 1).times do
        file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')
        report.photos.attach(file)
      end

      expect(report).not_to be_valid
      expect(report.errors[:photos]).to include("cannot exceed #{RentalConditionReport::MAX_PHOTOS} photos per report")
    end

    it 'validates photo file size' do
      # Create a blob that's too large (> 15MB)
      large_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('x' * 16.megabytes),
        filename: 'large.jpg',
        content_type: 'image/jpeg'
      )

      report.photos.attach(large_blob)

      expect(report).not_to be_valid
      expect(report.errors[:photos]).to include('must be less than 15MB each')
    end

    it 'validates photo content type' do
      invalid_file = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('not an image'),
        filename: 'file.txt',
        content_type: 'text/plain'
      )

      report.photos.attach(invalid_file)

      expect(report).not_to be_valid
      expect(report.errors[:photos]).to be_present
    end

    it 'supports HEIC image format' do
      heic_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('fake heic data'),
        filename: 'photo.heic',
        content_type: 'image/heic'
      )

      report.photos.attach(heic_blob)

      expect(report.photos).to be_attached
    end
  end

  describe 'helper methods' do
    let(:report) { create(:rental_condition_report, rental_booking: booking, staff_member: staff) }

    describe '#has_photos?' do
      it 'returns false when no photos attached' do
        expect(report.has_photos?).to be false
      end

      it 'returns true when photos are attached' do
        file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')
        report.photos.attach(file)

        expect(report.has_photos?).to be true
      end
    end

    describe '#photo_count' do
      it 'returns 0 when no photos attached' do
        expect(report.photo_count).to eq(0)
      end

      it 'returns correct count when photos are attached' do
        3.times do
          file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')
          report.photos.attach(file)
        end

        expect(report.photo_count).to eq(3)
      end
    end

    describe '#checkout?' do
      it 'returns true for checkout reports' do
        report = build(:rental_condition_report, :checkout, rental_booking: booking)
        expect(report.checkout?).to be true
      end

      it 'returns false for return reports' do
        report = build(:rental_condition_report, :return, rental_booking: booking)
        expect(report.checkout?).to be false
      end
    end

    describe '#return?' do
      it 'returns true for return reports' do
        report = build(:rental_condition_report, :return, rental_booking: booking)
        expect(report.return?).to be true
      end

      it 'returns false for checkout reports' do
        report = build(:rental_condition_report, :checkout, rental_booking: booking)
        expect(report.return?).to be false
      end
    end

    describe '#has_damage?' do
      it 'returns false when damage assessment is 0' do
        report = build(:rental_condition_report, rental_booking: booking, damage_assessment_amount: 0)
        expect(report.has_damage?).to be false
      end

      it 'returns true when damage assessment is greater than 0' do
        report = build(:rental_condition_report, rental_booking: booking, damage_assessment_amount: 25.50)
        expect(report.has_damage?).to be true
      end
    end

    describe '#condition_display' do
      it 'returns titleized condition rating' do
        report = build(:rental_condition_report, rental_booking: booking, condition_rating: 'good')
        expect(report.condition_display).to eq('Good')
      end

      it 'returns "Not rated" when no rating present' do
        report = build(:rental_condition_report, rental_booking: booking, condition_rating: nil)
        expect(report.condition_display).to eq('Not rated')
      end
    end

    describe '#staff_name' do
      it 'returns staff member name when present' do
        expect(report.staff_name).to eq(staff.name)
      end

      it 'returns "Unknown" when staff member not present' do
        report = build(:rental_condition_report, rental_booking: booking, staff_member: nil)
        expect(report.staff_name).to eq('Unknown')
      end
    end
  end

  describe 'scopes' do
    before do
      @checkout_report = create(:rental_condition_report, :checkout, rental_booking: booking, staff_member: staff)
      @return_report = create(:rental_condition_report, :return, rental_booking: booking, staff_member: staff)
    end

    it 'filters checkout reports' do
      expect(RentalConditionReport.checkout_reports).to include(@checkout_report)
      expect(RentalConditionReport.checkout_reports).not_to include(@return_report)
    end

    it 'filters return reports' do
      expect(RentalConditionReport.return_reports).to include(@return_report)
      expect(RentalConditionReport.return_reports).not_to include(@checkout_report)
    end
  end

  describe 'integration with rental booking' do
    it 'creates checkout report with photos during check_out!' do
      booking.mark_deposit_paid!(payment_intent_id: 'pi_test')
      booking.update!(start_time: 1.hour.ago)

      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')

      booking.check_out!(
        staff_member: staff,
        condition_notes: 'All items present',
        photos: [file]
      )

      checkout_report = booking.rental_condition_reports.checkout_reports.first
      expect(checkout_report).to be_present
      expect(checkout_report.has_photos?).to be true
      expect(checkout_report.photo_count).to eq(1)
    end

    it 'creates return report with photos during process_return!' do
      # Setup: mark as checked out first
      booking.mark_deposit_paid!(payment_intent_id: 'pi_test')
      booking.update!(status: 'checked_out', start_time: 2.days.ago, end_time: 1.day.ago, actual_pickup_time: 2.days.ago)

      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/test_image.jpg'), 'image/jpeg')

      booking.process_return!(
        staff_member: staff,
        condition_rating: 'good',
        notes: 'Returned in excellent condition',
        photos: [file]
      )

      return_report = booking.rental_condition_reports.return_reports.first
      expect(return_report).to be_present
      expect(return_report.has_photos?).to be true
      expect(return_report.photo_count).to eq(1)
    end
  end
end
