require 'rails_helper'

RSpec.describe Admin::ProductsController, type: :request do
  let(:admin_user) { create(:admin_user) }
  let(:product) { create(:product) }

  before do
    sign_in admin_user
    # Attach the same fixture image three times
    file = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg')
    3.times { product.images.attach(file) }
    product.reload
  end

  # Retrieve the ActiveStorage attachments for assertions
  let(:attachments) { product.images.attachments }
  let(:image1) { attachments[0] }
  let(:image2) { attachments[1] }
  let(:image3) { attachments[2] }

  describe "PUT /admin/products/:id" do
    context "with valid parameters" do
      it "sets the primary image" do
        put admin_product_path(product), params: { product: { images_attributes: [{ id: image2.id, primary: true }] } }
        
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(admin_product_path(product))
        
        product.reload
        expect(product.primary_image).to eq(image2)
      end

      it "reorders the images" do
        image_ids = [image3.id, image1.id, image2.id]
        put admin_product_path(product), params: { product: { images_attributes: image_ids.map.with_index { |id, index| { id: id, position: index } } } }
        
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(admin_product_path(product))
        
        product.reload
        expect(product.images.ordered.map(&:id)).to eq(image_ids)
      end

      it "sets the primary image and reorders in the same request" do
        image_ids = [image3.id, image1.id, image2.id]
        put admin_product_path(product), params: { 
          product: { 
            images_attributes: image_ids.map.with_index { |id, index| { id: id, position: index, primary: id == image2.id } }
          }
        }
        
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(admin_product_path(product))
        
        product.reload
        expect(product.primary_image).to eq(image2)
        expect(product.images.ordered.map(&:id)).to eq(image_ids)
      end

      it "returns an error when setting a non-existent image as primary" do
        put admin_product_path(product), params: { product: { images_attributes: [{ id: 999, primary: true }] } }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Image must exist")
      end
    end

    context "with invalid image order" do
      it "returns an error with an incomplete set of image IDs" do
        image_ids = [image1.id, image2.id]
        put admin_product_path(product), params: { product: { images_attributes: image_ids.map.with_index { |id, index| { id: id, position: index } } } }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Image IDs are incomplete")
      end

      it "returns an error with image IDs not belonging to the product" do
        # Attach the same fixture to another product to get a valid but unrelated attachment
        other_product = create(:product)
        other_file = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg')
        other_product.images.attach(other_file)
        other_product.reload
        other_attachment = other_product.images.attachments.first
        image_ids = [image1.id, other_attachment.id, image2.id]
        put admin_product_path(product), params: { product: { images_attributes: image_ids.map.with_index { |id, index| { id: id, position: index } } } }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Image must belong to the product")
      end

      it "returns an error with duplicate image IDs" do
        image_ids = [image1.id, image2.id, image2.id]
        put admin_product_path(product), params: { product: { images_attributes: image_ids.map.with_index { |id, index| { id: id, position: index } } } }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Image IDs must be unique")
      end
    end

    context "with invalid parameters" do
      it "returns an error response" do
        put admin_product_path(product), params: { product: { name: '' } }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Name can't be blank")
      end
    end
  end

  # TODO: Add tests for filters if they exist.
  # TODO: Add test case for product with images that exist but lack primary/position (if possible state)
end 