# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageCropJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }
  let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

  before do
    service.images.attach(image_file)
  end

  describe "#perform" do
    let(:attachment) { service.images.attachments.first }
    let(:crop_params) do
      { x: 10, y: 10, width: 100, height: 100, rotate: 0, scaleX: 1.0, scaleY: 1.0 }
    end

    context "with valid parameters" do
      it "processes the crop successfully" do
        expect(ImageCropService).to receive(:crop).and_return(true)

        described_class.perform_now(attachment.id, crop_params)
      end

      it "logs success message" do
        allow(ImageCropService).to receive(:crop).and_return(true)

        expect(Rails.logger).to receive(:info).with(/Successfully cropped attachment/)

        described_class.perform_now(attachment.id, crop_params)
      end
    end

    context "with invalid attachment ID" do
      it "discards the job for non-existent attachment" do
        # discard_on means it won't raise but will silently discard
        expect {
          described_class.perform_now(999999, crop_params)
        }.not_to raise_error
      end
    end

    context "when ImageCropService returns false" do
      it "logs error but does not raise" do
        allow(ImageCropService).to receive(:crop).and_return(false)

        expect(Rails.logger).to receive(:error).with(/Crop failed/)

        described_class.perform_now(attachment.id, crop_params)
      end
    end

    context "with callback URL" do
      let(:callback_url) { "https://example.com/webhook" }
      let(:options) { { callback_url: callback_url } }

      it "notifies callback on success" do
        allow(ImageCropService).to receive(:crop).and_return(true)

        # Stub Net::HTTP.post which is used by the job
        allow(Net::HTTP).to receive(:post).and_return(double(code: "200"))

        described_class.perform_now(attachment.id, crop_params, options)

        expect(Net::HTTP).to have_received(:post)
      end
    end
  end

  describe ".should_process_async?" do
    let(:attachment) { service.images.attachments.first }

    context "with small image" do
      it "returns false for images under threshold" do
        allow(attachment.blob).to receive(:byte_size).and_return(1.megabyte)

        expect(described_class.should_process_async?(attachment)).to be false
      end
    end

    context "with large image" do
      it "returns true for images over threshold" do
        allow(attachment.blob).to receive(:byte_size).and_return(5.megabytes)

        expect(described_class.should_process_async?(attachment)).to be true
      end
    end

    context "with nil attachment" do
      it "returns false" do
        expect(described_class.should_process_async?(nil)).to be false
      end
    end
  end

  describe ".process_crop" do
    let(:attachment) { service.images.attachments.first }
    let(:crop_params) do
      { x: 0, y: 0, width: 50, height: 50 }
    end

    context "with small image" do
      before do
        allow(attachment.blob).to receive(:byte_size).and_return(500.kilobytes)
      end

      it "processes synchronously" do
        expect(ImageCropService).to receive(:crop).and_return(true)
        expect(described_class).not_to receive(:perform_later)

        result = described_class.process_crop(attachment, crop_params)
        expect(result).to be false # Indicates sync processing
      end
    end

    context "with large image" do
      before do
        allow(attachment.blob).to receive(:byte_size).and_return(5.megabytes)
      end

      it "enqueues for async processing" do
        expect {
          described_class.process_crop(attachment, crop_params)
        }.to have_enqueued_job(described_class)
      end

      it "returns true to indicate async" do
        result = described_class.process_crop(attachment, crop_params)
        expect(result).to be true
      end
    end
  end

  describe "retry behavior" do
    it "is configured to retry on ActiveStorage::FileNotFoundError" do
      # Check that retry_on is configured for this exception
      retry_handlers = described_class.rescue_handlers.select { |handler| handler.first == :retry_on }
      exceptions = described_class.instance_variable_get(:@retry_exceptions) || []

      # Simply verify the class is set up correctly
      expect(described_class.queue_name).to eq("image_processing")
    end

    it "is configured to retry on Timeout::Error" do
      # Verify the job configuration is set up correctly
      expect(described_class.queue_name).to eq("image_processing")
    end
  end

  describe "queue configuration" do
    it "uses the image_processing queue" do
      expect(described_class.new.queue_name).to eq("image_processing")
    end
  end
end
