# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageCropService, type: :service do
  let(:business) { create(:business) }
  let(:service_record) { create(:service, business: business) }

  describe "#initialize" do
    context "with valid crop params as Hash" do
      let(:crop_params) { { x: 10, y: 20, width: 100, height: 100 } }

      it "normalizes the parameters" do
        service = described_class.new(nil, crop_params)
        expect(service.crop_params[:x]).to eq(10)
        expect(service.crop_params[:y]).to eq(20)
        expect(service.crop_params[:width]).to eq(100)
        expect(service.crop_params[:height]).to eq(100)
      end
    end

    context "with crop params as JSON string" do
      let(:crop_params) { '{"x": 15, "y": 25, "width": 150, "height": 150}' }

      it "parses and normalizes the parameters" do
        service = described_class.new(nil, crop_params)
        expect(service.crop_params[:x]).to eq(15)
        expect(service.crop_params[:y]).to eq(25)
        expect(service.crop_params[:width]).to eq(150)
        expect(service.crop_params[:height]).to eq(150)
      end
    end

    context "with invalid JSON string" do
      let(:crop_params) { "invalid json" }

      it "returns empty hash without raising" do
        service = described_class.new(nil, crop_params)
        expect(service.crop_params).to eq({})
      end
    end

    context "with rotation and scale params" do
      let(:crop_params) { { x: 0, y: 0, width: 100, height: 100, rotate: 90, scaleX: -1, scaleY: 1 } }

      it "includes rotation and scale values" do
        service = described_class.new(nil, crop_params)
        expect(service.crop_params[:rotate]).to eq(90)
        expect(service.crop_params[:scaleX]).to eq(-1.0)
        expect(service.crop_params[:scaleY]).to eq(1.0)
      end
    end
  end

  describe "#call" do
    context "without an attached image" do
      let(:crop_params) { { x: 0, y: 0, width: 100, height: 100 } }

      it "returns false and sets error" do
        service = described_class.new(nil, crop_params)
        expect(service.call).to be false
        expect(service.errors).to include("No image attached")
      end
    end

    context "with invalid crop dimensions" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }
      let(:crop_params) { { x: 0, y: 0, width: 5, height: 100 } }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
      end

      it "returns false when width is too small" do
        service = described_class.new(gallery_photo.image, crop_params)
        expect(service.call).to be false
        expect(service.errors).to include("Crop width must be at least 10px")
      end
    end

    context "with negative coordinates" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }
      let(:crop_params) { { x: -10, y: 0, width: 100, height: 100 } }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
      end

      it "returns false with coordinate error" do
        service = described_class.new(gallery_photo.image, crop_params)
        service.call
        expect(service.errors).to include("Crop coordinates cannot be negative")
      end
    end
  end

  describe ".crop" do
    context "with valid parameters" do
      it "creates instance and calls #call" do
        instance = instance_double(described_class)
        allow(described_class).to receive(:new).and_return(instance)
        allow(instance).to receive(:call).and_return(true)

        result = described_class.crop(nil, { x: 0, y: 0, width: 100, height: 100 })
        expect(result).to be true
      end
    end
  end

  describe ".crop!" do
    context "with no attachment" do
      it "raises CropError" do
        expect {
          described_class.crop!(nil, { x: 0, y: 0, width: 100, height: 100 })
        }.to raise_error(ImageCropService::CropError)
      end
    end

    context "with invalid crop dimensions" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
      end

      it "raises CropError for invalid dimensions" do
        expect {
          described_class.crop!(gallery_photo.image, { x: 0, y: 0, width: 5, height: 5 })
        }.to raise_error(ImageCropService::CropError, /Crop width must be at least/)
      end
    end
  end

  describe ".crop_attached_image" do
    context "when no image is attached" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }

      before do
        # Ensure no image is attached by purging any existing one
        gallery_photo.image.purge if gallery_photo.image.attached?
      end

      it "returns error hash" do
        result = described_class.crop_attached_image(gallery_photo, :image, { x: 0, y: 0, width: 100, height: 100 })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No image attached")
      end
    end

    context "when image is attached but crop fails" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
        # Mock the service to return failure
        allow_any_instance_of(described_class).to receive(:call).and_return(false)
        allow_any_instance_of(described_class).to receive(:errors).and_return(["Crop failed"])
      end

      it "returns error hash from service" do
        result = described_class.crop_attached_image(gallery_photo, :image, { x: 0, y: 0, width: 100, height: 100 })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Crop failed")
      end
    end

    context "when crop succeeds" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
        # Mock the service to return success
        allow_any_instance_of(described_class).to receive(:call).and_return(true)
      end

      it "returns success hash" do
        result = described_class.crop_attached_image(gallery_photo, :image, { x: 0, y: 0, width: 100, height: 100 })
        expect(result[:success]).to be true
      end
    end

    context "when an exception occurs" do
      let(:gallery_photo) { create(:gallery_photo, business: business) }

      before do
        gallery_photo.image.attach(
          io: StringIO.new("fake image data"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
        allow_any_instance_of(described_class).to receive(:call).and_raise(StandardError.new("Something went wrong"))
      end

      it "catches exception and returns error hash" do
        result = described_class.crop_attached_image(gallery_photo, :image, { x: 0, y: 0, width: 100, height: 100 })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Something went wrong")
      end
    end
  end

  describe "constants" do
    it "has MAX_DIMENSION set to 4096" do
      expect(described_class::MAX_DIMENSION).to eq(4096)
    end

    it "has MIN_CROP_SIZE set to 10" do
      expect(described_class::MIN_CROP_SIZE).to eq(10)
    end
  end

  describe "error classes" do
    it "CropError inherits from StandardError" do
      expect(ImageCropService::CropError.superclass).to eq(StandardError)
    end

    it "InvalidParamsError inherits from CropError" do
      expect(ImageCropService::InvalidParamsError.superclass).to eq(ImageCropService::CropError)
    end

    it "AttachmentNotFoundError inherits from CropError" do
      expect(ImageCropService::AttachmentNotFoundError.superclass).to eq(ImageCropService::CropError)
    end
  end
end
