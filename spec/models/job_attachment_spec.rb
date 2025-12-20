# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobAttachment, type: :model do
  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }

  subject(:attachment) { build(:job_attachment, business: business, attachable: service) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:attachable) }
    it { is_expected.to belong_to(:uploaded_by_user).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business) }
    it { is_expected.to validate_presence_of(:attachable) }
    it { is_expected.to validate_presence_of(:attachment_type) }
    it { is_expected.to validate_presence_of(:visibility) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
    it { is_expected.to validate_length_of(:description).is_at_most(2000) }
    it { is_expected.to validate_length_of(:instructions).is_at_most(5000) }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:attachment_type)
        .with_values(before_photo: 0, after_photo: 1, instruction: 2, reference_file: 3, general: 4)
    end

    it do
      is_expected.to define_enum_for(:visibility)
        .with_values(internal: 0, customer_visible: 1)
        .with_prefix(:visibility)
    end
  end

  describe 'scopes' do
    let!(:before_photo) { create(:job_attachment, business: business, attachable: service, attachment_type: :before_photo) }
    let!(:after_photo) { create(:job_attachment, :after_photo, business: business, attachable: service) }
    let!(:instruction) { create(:job_attachment, :instruction, business: business, attachable: service) }
    let!(:internal_attachment) { create(:job_attachment, business: business, attachable: service, visibility: :internal) }
    let!(:visible_attachment) { create(:job_attachment, :customer_visible, business: business, attachable: service) }

    describe '.photos' do
      it 'returns before and after photos' do
        expect(JobAttachment.photos).to contain_exactly(before_photo, after_photo)
      end
    end

    describe '.before_photos' do
      it 'returns only before photos' do
        expect(JobAttachment.before_photos).to contain_exactly(before_photo)
      end
    end

    describe '.after_photos' do
      it 'returns only after photos' do
        expect(JobAttachment.after_photos).to contain_exactly(after_photo)
      end
    end

    describe '.instructions' do
      it 'returns only instruction attachments' do
        expect(JobAttachment.instructions).to contain_exactly(instruction)
      end
    end

    describe '.visible_to_customer' do
      it 'returns customer-visible attachments' do
        expect(JobAttachment.visible_to_customer).to contain_exactly(visible_attachment)
      end
    end

    describe '.internal_only' do
      it 'returns internal-only attachments' do
        # All attachments except visible_attachment
        expect(JobAttachment.internal_only).to include(internal_attachment)
        expect(JobAttachment.internal_only).not_to include(visible_attachment)
      end
    end
  end

  describe 'polymorphic attachment' do
    it 'can be attached to a service' do
      service_attachment = create(:job_attachment, business: business, attachable: service)
      expect(service_attachment.attachable).to eq(service)
    end

    it 'can be attached to a booking' do
      booking = create(:booking, business: business, service: service)
      booking_attachment = create(:job_attachment, business: business, attachable: booking)
      expect(booking_attachment.attachable).to eq(booking)
    end

    it 'can be attached to an estimate' do
      estimate = create(:estimate, business: business)
      estimate_attachment = create(:job_attachment, business: business, attachable: estimate)
      expect(estimate_attachment.attachable).to eq(estimate)
    end
  end

  describe '#display_name' do
    it 'returns title when present' do
      attachment.title = 'My Title'
      expect(attachment.display_name).to eq('My Title')
    end

    it 'returns filename when title is blank and file attached' do
      attachment.title = nil
      allow(attachment).to receive(:file).and_return(double(attached?: true, filename: 'test.jpg'))

      expect(attachment.display_name).to eq('test.jpg')
    end
  end

  describe '#image?' do
    it 'returns true for image content types' do
      allow(attachment).to receive(:file).and_return(double(attached?: true, content_type: 'image/jpeg'))
      expect(attachment.image?).to be true
    end

    it 'returns false for non-image content types' do
      allow(attachment).to receive(:file).and_return(double(attached?: true, content_type: 'application/pdf'))
      expect(attachment.image?).to be false
    end

    it 'returns false when no file attached' do
      allow(attachment).to receive(:file).and_return(double(attached?: false))
      expect(attachment.image?).to be false
    end
  end

  describe '#pdf?' do
    it 'returns true for PDF files' do
      allow(attachment).to receive(:file).and_return(double(attached?: true, content_type: 'application/pdf'))
      expect(attachment.pdf?).to be true
    end

    it 'returns false for non-PDF files' do
      allow(attachment).to receive(:file).and_return(double(attached?: true, content_type: 'image/jpeg'))
      expect(attachment.pdf?).to be false
    end
  end

  describe 'position auto-assignment' do
    it 'sets position to next available value' do
      attachment1 = create(:job_attachment, business: business, attachable: service, position: 0)
      attachment2 = create(:job_attachment, business: business, attachable: service)

      expect(attachment2.position).to eq(1)
    end
  end

  describe 'with uploaded_by_user' do
    it 'tracks who uploaded the attachment' do
      user = create(:user)
      attachment = create(:job_attachment, :with_uploaded_by, business: business, attachable: service, uploaded_by_user: user)

      expect(attachment.uploaded_by_user).to eq(user)
    end
  end
end
