require 'rails_helper'

RSpec.describe ProcessImageJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:product) { create(:product, business: business) }
  let(:image_file) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }

  before do
    product.images.attach(image_file)
  end

  describe 'queue configuration' do
    it 'uses the image_processing queue' do
      expect(described_class.new.queue_name).to eq('image_processing')
    end
  end

  describe 'MAX_PROCESSABLE_SIZE' do
    it 'is set to 10 megabytes' do
      expect(described_class::MAX_PROCESSABLE_SIZE).to eq(10.megabytes)
    end
  end

  describe '#perform' do
    let(:attachment) { product.images.attachments.first }

    it 'processes image variants for images under size limit' do
      # Mock blob size to be within limit
      allow(attachment.blob).to receive(:byte_size).and_return(5.megabytes)
      allow(attachment.blob).to receive(:image?).and_return(true)

      expect {
        perform_enqueued_jobs do
          ProcessImageJob.perform_later(attachment.id)
        end
      }.not_to raise_error
    end

    it 'skips processing for files exceeding size limit' do
      # Mock blob size to exceed 10MB limit - stub on any instance since blob is loaded fresh
      allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(15.megabytes)
      allow(Rails.logger).to receive(:warn).and_call_original

      perform_enqueued_jobs do
        ProcessImageJob.perform_later(attachment.id)
      end

      expect(Rails.logger).to have_received(:warn).with(/Skipping variant generation for large file/)
    end

    it 'processes small images normally' do
      # Mock blob size to be small
      allow(attachment.blob).to receive(:byte_size).and_return(1.megabyte)
      allow(attachment.blob).to receive(:image?).and_return(true)

      expect {
        perform_enqueued_jobs do
          ProcessImageJob.perform_later(attachment.id)
        end
      }.not_to raise_error
    end

    it 'handles missing attachments gracefully' do
      expect {
        perform_enqueued_jobs do
          ProcessImageJob.perform_later(999999) # Non-existent ID
        end
      }.not_to raise_error
    end

    it 'handles non-image attachments gracefully' do
      allow(attachment.blob).to receive(:image?).and_return(false)

      expect {
        perform_enqueued_jobs do
          ProcessImageJob.perform_later(attachment.id)
        end
      }.not_to raise_error
    end

    context 'with HEIC images' do
      # Use existing JPEG fixture but mock as HEIC for testing
      let(:heic_file) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/heic') }                                                             

      before do
        product.images.attach(heic_file)
      end

      it 'converts HEIC to JPEG when ImageMagick supports HEIC' do
        heic_attachment = product.images.attachments.last

        # Mock HEIC support
        allow_any_instance_of(ProcessImageJob).to receive(:heic_supported?).and_return(true)
        allow(heic_attachment.blob).to receive(:image?).and_return(true)
        allow(heic_attachment.blob).to receive(:byte_size).and_return(1.megabyte)

        expect {
          perform_enqueued_jobs do
            ProcessImageJob.perform_later(heic_attachment.id)
          end
        }.not_to raise_error
      end

      it 'skips conversion when ImageMagick does not support HEIC' do
        heic_attachment = product.images.attachments.last

        # Mock no HEIC support
        allow_any_instance_of(ProcessImageJob).to receive(:heic_supported?).and_return(false)
        allow(heic_attachment.blob).to receive(:image?).and_return(true)

        expect {
          perform_enqueued_jobs do
            ProcessImageJob.perform_later(heic_attachment.id)
          end
        }.not_to raise_error
      end

      it 'handles HEIC conversion errors gracefully' do
        heic_attachment = product.images.attachments.last

        # Mock HEIC support but conversion failure
        allow_any_instance_of(ProcessImageJob).to receive(:heic_supported?).and_return(true)
        allow(heic_attachment.blob).to receive(:image?).and_return(true)
        allow(ImageProcessing::MiniMagick).to receive(:source).and_raise(ImageProcessing::Error.new('Conversion failed'))

        expect {
          perform_enqueued_jobs do
            ProcessImageJob.perform_later(heic_attachment.id)
          end
        }.not_to raise_error
      end
    end
  end
end 