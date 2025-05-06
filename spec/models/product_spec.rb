# spec/models/product_spec.rb
require 'rails_helper'

RSpec.describe Product, type: :model do
  let(:business) { create(:business) }
  let(:category) { create(:category, business: business) }

  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:category).optional }
    it { should have_many(:product_variants).dependent(:destroy) }
    it { should have_many(:line_items).through(:product_variants) }
    it { should have_many_attached(:images) }
    it { should accept_nested_attributes_for(:product_variants).allow_destroy(true) }
  end

  describe 'validations' do
    subject { build(:product, business: business, category: category) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:business_id) }
    it { should validate_presence_of(:price) }
    it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }

    # Active Storage validations (ensure test helper is configured)
    # it { should validate_attached_of(:images) } # Attachment is optional
    it { should validate_content_type_of(:images).allowing('image/png', 'image/jpeg') }
    it { should validate_content_type_of(:images).rejecting('text/plain', 'application/pdf') }
    it { should validate_size_of(:images).less_than(5.megabytes) }
  end

  describe 'scopes' do
    let!(:active_product) { create(:product, business: business, active: true) }
    let!(:inactive_product) { create(:product, business: business, active: false) }
    let!(:featured_product) { create(:product, business: business, featured: true) }
    let!(:unfeatured_product) { create(:product, business: business, featured: false) }

    it '.active returns only active products' do
      expect(Product.active).to contain_exactly(active_product, featured_product, unfeatured_product)
      expect(Product.active).not_to include(inactive_product)
    end

    it '.featured returns only featured products' do
      expect(Product.featured).to contain_exactly(featured_product)
      expect(Product.featured).not_to include(active_product, inactive_product, unfeatured_product)
    end
  end

  # Add tests for TenantScoped concern if not covered elsewhere
  # ...

  describe 'nested attributes' do
    it 'allows creation of product variants via nested attributes' do
      # Create product first, without variants, ensuring it's valid (e.g., needs business, category)
      product = create(:product, business: business, category: category)
      # Now update with nested attributes
      expect {
        product.update!({
          product_variants_attributes: [
            attributes_for(:product_variant, name: 'Small', stock_quantity: 10),
            attributes_for(:product_variant, name: 'Large', stock_quantity: 5)
          ]
        })
      }.to change(ProductVariant, :count).by(2)
      product.reload
      expect(product.product_variants.count).to eq(2)
      expect(product.product_variants.find_by(name: 'Small').stock_quantity).to eq(10)
    end
  end

  describe 'images' do
    let(:product) { create(:product, business: business, category: category) }
    let(:image1) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }
    let(:image2) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }
    let(:image3) { fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg') }

    before do
      product.images.attach(image1, image2, image3)
    end

    describe '#primary_image' do
      it 'returns nil when no primary image is set' do
        expect(product.primary_image).to be_nil
      end

      it 'returns the primary image when set' do
        product.images.second.update(primary: true)
        expect(product.primary_image).to eq(product.images.second)
      end

      it 'returns a single image when multiple are marked as primary' do
        product.images.first.update(primary: true)
        product.images.second.update(primary: true)
        
        expect(product.primary_image).to eq(product.images.first)
      end
    end

    describe '#set_primary_image' do
      it 'sets the given image as primary and unsets any previous primary' do
        product.images.first.update(primary: true)
        product.set_primary_image(product.images.last)
        expect(product.images.first.reload.primary).to be false
        expect(product.images.last.reload.primary).to be true
      end

      it 'ensures only one image remains as primary when multiple are initially set' do
        product.images.first.update(primary: true)
        product.images.second.update(primary: true)
        
        product.set_primary_image(product.images.last)
        
        expect(product.images.first.reload.primary).to be false
        expect(product.images.second.reload.primary).to be false
        expect(product.images.last.reload.primary).to be true
      end
    end

    describe '#reorder_images' do
      it 'updates the position of images based on the given order' do
        product.reorder_images([product.images.last.id, product.images.second.id, product.images.first.id])
        expect(product.images.ordered.map(&:id)).to eq([product.images.last.id, product.images.second.id, product.images.first.id])
      end
    end

    describe '#images.ordered' do
      it 'returns images ordered by position' do
        product.images.each_with_index do |image, index|
          image.update(position: index)
        end
        expect(product.images.ordered.map(&:id)).to eq(product.images.map(&:id))
      end
    end
  end
end 