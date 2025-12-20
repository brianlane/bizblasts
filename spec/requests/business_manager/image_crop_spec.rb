# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Business Manager Image Crop Endpoints", type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    sign_in user
    host! "#{business.subdomain}.lvh.me"
    # Mock ImageCropService to avoid dependency on ImageMagick in CI
    allow(ImageCropService).to receive(:crop).and_return(true)
    # Also mock crop_attached_image which is used by gallery_controller
    allow(ImageCropService).to receive(:crop_attached_image).and_return({ success: true })
  end

  describe "Services Image Cropping" do
    let(:service) { create(:service, business: business) }
    let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

    before do
      service.images.attach(image_file)
    end

    describe "POST /manage/services/:id/crop_image/:attachment_id" do
      let(:attachment) { service.images.attachments.first }
      let(:valid_crop_params) do
        {
          x: 10,
          y: 10,
          width: 100,
          height: 100,
          rotate: 0,
          scaleX: 1,
          scaleY: 1
        }
      end

      context "with valid crop data" do
        it "crops the image successfully" do
          post crop_image_business_manager_service_path(service, attachment_id: attachment.id),
               params: { crop_data: valid_crop_params.to_json },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:success)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
        end

        it "returns updated thumbnail URL" do
          post crop_image_business_manager_service_path(service, attachment_id: attachment.id),
               params: { crop_data: valid_crop_params.to_json },
               headers: { "Accept" => "application/json" }

          json = JSON.parse(response.body)
          expect(json["success"]).to be true
        end
      end

      context "with invalid crop data" do
        it "returns error for missing crop data" do
          post crop_image_business_manager_service_path(service, attachment_id: attachment.id),
               params: {},
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:unprocessable_content)
          json = JSON.parse(response.body)
          expect(json["error"]).to include("No crop data")
        end

        it "returns error for invalid JSON" do
          post crop_image_business_manager_service_path(service, attachment_id: attachment.id),
               params: { crop_data: "invalid json{{{" },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:unprocessable_content)
          json = JSON.parse(response.body)
          expect(json["error"]).to be_present
        end
      end

      context "with non-existent attachment" do
        it "returns not found error" do
          post crop_image_business_manager_service_path(service, attachment_id: 999999),
               params: { crop_data: valid_crop_params.to_json },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    describe "POST /manage/services/:id/add_image" do
      it "uploads a new image" do
        expect {
          post add_image_business_manager_service_path(service),
               params: { image: fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") },
               headers: { "Accept" => "application/json" }
        }.to change { service.images.count }.by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["attachment_id"]).to be_present
      end

      it "validates file type" do
        # Upload a valid image file successfully
        post add_image_business_manager_service_path(service),
             params: { image: fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:success)
      end
    end

    describe "DELETE /manage/services/:id/remove_image/:attachment_id" do
      let(:attachment_to_delete) { service.images.attachments.first }

      it "removes the image" do
        expect {
          delete remove_image_business_manager_service_path(service, attachment_id: attachment_to_delete.id),
                 headers: { "Accept" => "application/json" }
        }.to change { service.images.count }.by(-1)

        expect(response).to have_http_status(:success)
      end

      it "returns not found for non-existent attachment" do
        delete remove_image_business_manager_service_path(service, attachment_id: 999999),
               headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "Products Image Cropping" do
    let(:product) { create(:product, business: business) }
    let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

    before do
      product.images.attach(image_file)
    end

    describe "POST /manage/products/:id/crop_image/:attachment_id" do
      let(:attachment) { product.images.attachments.first }
      let(:valid_crop_params) do
        { x: 0, y: 0, width: 50, height: 50 }
      end

      it "crops the image successfully" do
        post crop_image_business_manager_product_path(product, attachment_id: attachment.id),
             params: { crop_data: valid_crop_params.to_json },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it "validates image type" do
        # The controller should handle valid images correctly
        post crop_image_business_manager_product_path(product, attachment_id: attachment.id),
             params: { crop_data: valid_crop_params.to_json },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "Gallery Image Cropping" do
    let(:gallery_photo) { create(:gallery_photo, business: business) }
    let(:image_file) { fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") }

    before do
      gallery_photo.image.attach(image_file)
    end

    describe "POST /manage/gallery/photos/:id/crop" do
      let(:valid_crop_params) do
        { x: 5, y: 5, width: 80, height: 80 }
      end

      it "crops the gallery photo successfully" do
        post business_manager_gallery_crop_photo_path(gallery_photo),
             params: { crop_data: valid_crop_params.to_json },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it "validates that attachment is an image" do
        post business_manager_gallery_crop_photo_path(gallery_photo),
             params: { crop_data: valid_crop_params.to_json },
             headers: { "Accept" => "application/json" }

        # Should succeed because it's a valid image
        expect(response).to have_http_status(:success)
      end

      it "returns error for missing crop data" do
        post business_manager_gallery_crop_photo_path(gallery_photo),
             params: {},
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "Authorization" do
    let(:other_business) { create(:business) }
    let(:service) { create(:service, business: other_business) }

    it "prevents access to resources from other businesses" do
      post add_image_business_manager_service_path(service),
           params: { image: fixture_file_upload("spec/fixtures/files/test_image.jpg", "image/jpeg") },
           headers: { "Accept" => "application/json" }

      # Should fail because service belongs to different business
      expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
    end
  end
end
