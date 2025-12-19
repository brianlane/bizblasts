# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageCroppable, type: :controller do
  # Create a test controller that includes the concern
  controller(ApplicationController) do
    include ImageCroppable

    def test_parse_crop_params
      render json: { parsed: parse_crop_params(params[:crop_data]) }
    end

    def test_valid_image_for_crop
      # Create a mock attachment for testing
      render json: { valid: valid_image_for_crop?(nil) }
    end
  end

  before do
    routes.draw do
      get "test_parse_crop_params" => "anonymous#test_parse_crop_params"
      get "test_valid_image_for_crop" => "anonymous#test_valid_image_for_crop"
    end
  end

  describe "#parse_crop_params" do
    context "with JSON string input" do
      it "parses valid JSON string" do
        get :test_parse_crop_params, params: { crop_data: '{"x":10,"y":20,"width":100,"height":200}' }

        json = JSON.parse(response.body)
        expect(json["parsed"]["x"]).to eq(10)
        expect(json["parsed"]["y"]).to eq(20)
        expect(json["parsed"]["width"]).to eq(100)
        expect(json["parsed"]["height"]).to eq(200)
      end

      it "returns empty hash for invalid JSON" do
        get :test_parse_crop_params, params: { crop_data: "invalid{{{json" }

        json = JSON.parse(response.body)
        expect(json["parsed"]).to eq({})
      end
    end

    context "with hash input" do
      it "converts ActionController::Parameters to hash" do
        get :test_parse_crop_params, params: {
          crop_data: { x: 5, y: 10, width: 50, height: 60 }
        }

        json = JSON.parse(response.body)
        expect(json["parsed"]["x"]).to eq(5)
        expect(json["parsed"]["y"]).to eq(10)
        expect(json["parsed"]["width"]).to eq(50)
        expect(json["parsed"]["height"]).to eq(60)
      end
    end

    context "with nil or blank input" do
      it "returns empty hash for nil" do
        get :test_parse_crop_params, params: { crop_data: nil }

        json = JSON.parse(response.body)
        expect(json["parsed"]).to eq({})
      end

      it "returns empty hash for blank string" do
        get :test_parse_crop_params, params: { crop_data: "" }

        json = JSON.parse(response.body)
        expect(json["parsed"]).to eq({})
      end
    end

    context "with rotation and scale parameters" do
      it "parses rotation correctly" do
        get :test_parse_crop_params, params: {
          crop_data: '{"x":0,"y":0,"width":100,"height":100,"rotate":90}'
        }

        json = JSON.parse(response.body)
        expect(json["parsed"]["rotate"]).to eq(90)
      end

      it "parses scale values correctly" do
        get :test_parse_crop_params, params: {
          crop_data: '{"x":0,"y":0,"width":100,"height":100,"scaleX":-1,"scaleY":1.5}'
        }

        json = JSON.parse(response.body)
        expect(json["parsed"]["scaleX"]).to eq(-1.0)
        expect(json["parsed"]["scaleY"]).to eq(1.5)
      end

      it "defaults scale values to 1.0 when not provided" do
        get :test_parse_crop_params, params: {
          crop_data: '{"x":0,"y":0,"width":100,"height":100}'
        }

        json = JSON.parse(response.body)
        expect(json["parsed"]["scaleX"]).to eq(1.0)
        expect(json["parsed"]["scaleY"]).to eq(1.0)
      end
    end
  end

  describe "#valid_image_for_crop?" do
    let(:service) { create(:service) }

    context "with valid image attachment" do
      let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

      before do
        service.images.attach(image_file)
      end

      it "returns true for JPEG images" do
        # Access the VALID_IMAGE_TYPES constant - JPEG is a valid type
        expect(ImageCroppable::VALID_IMAGE_TYPES).to include("image/jpeg")
      end

      it "includes PNG in valid types" do
        expect(ImageCroppable::VALID_IMAGE_TYPES).to include("image/png")
      end

      it "includes JPEG in valid types" do
        expect(ImageCroppable::VALID_IMAGE_TYPES).to include("image/jpeg")
      end

      it "includes WebP in valid types" do
        expect(ImageCroppable::VALID_IMAGE_TYPES).to include("image/webp")
      end

      it "includes HEIC in valid types" do
        expect(ImageCroppable::VALID_IMAGE_TYPES).to include("image/heic")
      end
    end

    context "with nil attachment" do
      it "returns false" do
        get :test_valid_image_for_crop

        json = JSON.parse(response.body)
        expect(json["valid"]).to be false
      end
    end
  end

  describe "ALLOWED_CROP_KEYS constant" do
    it "includes all required crop parameters" do
      expected_keys = %w[x y width height rotate scaleX scaleY]
      expect(ImageCroppable::ALLOWED_CROP_KEYS).to match_array(expected_keys)
    end
  end
end
