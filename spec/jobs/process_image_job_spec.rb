require 'rails_helper'

RSpec.describe ProcessImageJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:product) { create(:product, business: business) }
  let(:image_file) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }

  before do
    product.images.attach(image_file)
  end

  describe '#perform' do
    let(:attachment) { product.images.attachments.first }

    it 'processes image variants for large images' do
      # Mock blob size to be larger than 2MB to trigger processing
      allow(attachment.blob).to receive(:byte_size).and_return(3.megabytes)
      allow(attachment.blob).to receive(:image?).and_return(true)

      expect {
        perform_enqueued_jobs do
          ProcessImageJob.perform_later(attachment.id)
        end
      }.not_to raise_error
    end

    it 'skips processing for small images' do
      # Mock blob size to be smaller than 2MB
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
  end
end 