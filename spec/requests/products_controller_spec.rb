require 'rails_helper'

RSpec.describe ProductsController, type: :request do
  # Include route helpers for request specs
  include Rails.application.routes.url_helpers

  let(:business) { create(:business) }
  let(:category1) { create(:category, business: business) }
  let(:category2) { create(:category, business: business) }
  let!(:product1) { create(:product, business: business, category: category1, name: 'Product 1', description: 'Description 1') }
  let!(:product2) { create(:product, business: business, category: category2, name: 'Product 2', description: 'Description 2') }
  let!(:variant1) { create(:product_variant, product: product1) }
  let!(:variant2) { create(:product_variant, product: product1) }

  before do
    # Explicitly set the request host for the request spec
    host! "#{business.subdomain}.example.com"
    # Load two different fixture files
    file1 = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg')
    file2 = fixture_file_upload('spec/fixtures/files/new-item.jpg', 'image/jpeg') # Use the new fixture
    product1.images.attach([file1, file2]) # Attach as an array
    product1.reload
    # Manually set the current tenant for ActsAsTenant in this request spec context
    ActsAsTenant.current_tenant = business
  end

  let(:images) { product1.images.attachments }
  let(:image1) { images[0] }
  let(:image2) { images[1] }

  describe "GET /products" do
    it "returns a success response" do
      get products_path
      expect(response).to have_http_status(:success)
    end

    it "filters products by category" do
      get products_path(category_id: category1.id)
      expect(response.body).to include(product1.name)
      expect(response.body).not_to include(product2.name)
    end

    it "searches products by name" do
      get products_path(q: { name_cont: 'Product 1' })
      expect(response.body).to include(product1.name)
      expect(response.body).not_to include(product2.name)
    end

    it "searches products by description" do
      get products_path(q: { description_cont: 'Description 2' })
      expect(response.body).not_to include(product1.name)
      expect(response.body).to include(product2.name)
    end

    context "with invalid category ID" do
      it "redirects to index with flash message" do
        get products_path(category_id: 'invalid')
        expect(response).to redirect_to(products_path)
        expect(flash[:alert]).to eq("Category not found")
      end
    end

    context "pagination" do
      let!(:products) { create_list(:product, 5, business: business) }

      it "returns the correct number of products per page" do
        get products_path
        expect(response.body).to include(products[0].name)
        expect(response.body).to include(products[1].name)
        expect(response.body).not_to include(products[2].name)
      end

      it "returns the correct products for a given page" do
        get products_path(page: 2)
        expect(response.body).to include(products[2].name)
        expect(response.body).to include(products[3].name)
        expect(response.body).not_to include(products[0].name)
      end

      it "handles invalid page parameter" do
        get products_path(page: 'invalid')
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(products[0].name)
        expect(response.body).to include(products[1].name)
      end
    end
  end

  describe "GET /products/:id" do
    it "returns a success response" do
      get product_path(product1)
      expect(response).to have_http_status(:success)
    end

    it "selects the specified variant" do
      get product_path(product1, variant_id: variant2.id)
      expect(assigns(:variant)).to eq(variant2)
    end

    it "selects the first variant by default" do
      get product_path(product1)
      expect(assigns(:variant)).to eq(variant1)
    end

    it "assigns the product images" do
      get product_path(product1)
      expect(assigns(:images)).to match_array([image1, image2])
    end

    context "with invalid variant ID" do
      it "redirects to show with flash message" do
        get product_path(product1, variant_id: 'invalid')
        expect(response).to redirect_to(product_path(product1))
        expect(flash[:alert]).to eq("Variant not found")
      end
    end
  end
end 