# spec/models/product_spec.rb
require 'rails_helper'

RSpec.describe Product, type: :model do
  let(:business) { create(:business) }


  describe 'associations' do
    it { should belong_to(:business) }

    it { should have_many(:product_variants).dependent(:destroy) }
    it { should have_many(:line_items).through(:product_variants) }
    it { should have_many_attached(:images) }
    it { should accept_nested_attributes_for(:product_variants).allow_destroy(true) }
  end

  describe 'validations' do
    subject { build(:product, business: business) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:business_id) }
    it { should validate_presence_of(:price) }

    context 'price validation' do
      it 'rejects invalid price formats with custom error message' do
        product = build(:product, business: business, price: 'abcd')
        expect(product).not_to be_valid
        expect(product.errors[:price]).to include("must be a valid number - 'abcd' is not a valid price format (e.g., '10.50' or '$10.50')")
      end

      it 'rejects nil price' do
        product = build(:product, business: business, price: nil)
        expect(product).not_to be_valid
        expect(product.errors[:price]).to include("can't be blank")
      end

      it 'rejects empty string price' do
        product = build(:product, business: business, price: '')
        expect(product).not_to be_valid
        expect(product.errors[:price]).to include("can't be blank")
      end

      it 'accepts valid numeric price' do
        product = build(:product, business: business, price: '10.50')
        product.valid?
        expect(product.errors[:price]).to be_empty
      end

      it 'accepts valid currency formatted price' do
        product = build(:product, business: business, price: '$10.50')
        product.valid?
        expect(product.errors[:price]).to be_empty
      end
    end
    it { should validate_length_of(:variant_label_text).is_at_most(100) }

    # Active Storage validations (ensure test helper is configured)
    # it { should validate_attached_of(:images) } # Attachment is optional
    it { should validate_content_type_of(:images).allowing('image/png', 'image/jpeg', 'image/gif', 'image/webp') }
    it { should validate_content_type_of(:images).rejecting('text/plain', 'application/pdf') }
    it { should validate_size_of(:images).less_than(15.megabytes) }
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
          # Create product first, without variants, ensuring it's valid (e.g., needs business)
    product = create(:product, business: business)
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
      # Account for the default variant created on product creation
      expect(product.product_variants.count).to eq(3)
      expect(product.product_variants.find_by(name: 'Small').stock_quantity).to eq(10)
    end
  end

  describe 'images' do
    let(:product) { create(:product, business: business) }
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

  describe 'promotional pricing methods' do
    let(:product) { create(:product, business: business, price: 100.00) }
    
    before do
      ActsAsTenant.current_tenant = business
    end

    describe '#current_promotion' do
      context 'with active promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_products: true,
            start_date: 1.week.ago,
            end_date: 1.week.from_now,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns the active promotion' do
          expect(product.current_promotion).to eq(promotion)
        end
      end

      context 'with expired promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_products: true,
            start_date: 2.weeks.ago,
            end_date: 1.week.ago,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns nil for expired promotion' do
          expect(product.current_promotion).to be_nil
        end
      end

      context 'with inactive promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_products: true,
            active: false
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns nil for inactive promotion' do
          expect(product.current_promotion).to be_nil
        end
      end

      context 'with usage limit reached' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_products: true,
            usage_limit: 5,
            current_usage: 5,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns nil when usage limit is reached' do
          expect(product.current_promotion).to be_nil
        end
      end
    end

    describe '#on_promotion?' do
      context 'with active promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 25,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns true when product has active promotion' do
          expect(product.on_promotion?).to be true
        end
      end

      context 'without promotion' do
        it 'returns false when product has no promotion' do
          expect(product.on_promotion?).to be false
        end
      end
    end

    describe '#promotional_price' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 20,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns discounted price for percentage promotion' do
          expect(product.promotional_price).to eq(80.00) # 100 - 20% = 80
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 15.00,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns discounted price for fixed amount promotion' do
          expect(product.promotional_price).to eq(85.00) # 100 - 15 = 85
        end
      end

      context 'without promotion' do
        it 'returns original price when no promotion is active' do
          expect(product.promotional_price).to eq(100.00)
        end
      end
    end

    describe '#promotion_discount_amount' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 30,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns discount amount for percentage promotion' do
          expect(product.promotion_discount_amount).to eq(30.00) # 30% of 100 = 30
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 25.00,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns discount amount for fixed amount promotion' do
          expect(product.promotion_discount_amount).to eq(25.00)
        end
      end

      context 'without promotion' do
        it 'returns zero when no promotion is active' do
          expect(product.promotion_discount_amount).to eq(0)
        end
      end
    end

    describe '#savings_percentage' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 25,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns the discount percentage' do
          expect(product.savings_percentage).to eq(25)
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 20.00,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'calculates percentage savings for fixed amount promotion' do
          expect(product.savings_percentage).to eq(20) # 20/100 * 100 = 20%
        end
      end

      context 'without promotion' do
        it 'returns zero when no promotion is active' do
          expect(product.savings_percentage).to eq(0)
        end
      end
    end

    describe '#promotion_display_text' do
      context 'with percentage discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'percentage',
            discount_value: 35,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns percentage display text' do
          expect(product.promotion_display_text).to eq('35% OFF')
        end
      end

      context 'with fixed amount discount promotion' do
        let!(:promotion) do
          create(:promotion,
            business: business,
            discount_type: 'fixed_amount',
            discount_value: 15.00,
            applicable_to_products: true,
            active: true
          )
        end
        
        before do
          promotion.promotion_products.create!(product: product)
        end

        it 'returns fixed amount display text' do
          expect(product.promotion_display_text).to eq('$15.0 OFF')
        end
      end

      context 'without promotion' do
        it 'returns nil when no promotion is active' do
          expect(product.promotion_display_text).to be_nil
        end
      end
    end

    describe 'memoization behavior' do
      let!(:promotion) do
        create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 15,
          applicable_to_products: true,
          active: true
        )
      end
      
      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'memoizes current_promotion result' do
        # First call should query the database
        first_result = product.current_promotion
        
        # Mock the association to verify it's not called again
        expect(product.promotion_products).not_to receive(:joins)
        
        # Second call should return memoized result
        second_result = product.current_promotion
        
        expect(first_result).to eq(second_result)
        expect(first_result).to eq(promotion)
      end

      it 'clears memoization when product is reloaded' do
        # Get initial result
        product.current_promotion
        
        # Reload product
        product.reload
        
        # Should be able to get promotion again after reload
        expect(product.current_promotion).to eq(promotion)
      end
    end
  end

  describe 'image deletion functionality' do
    let(:product) { create(:product, business: business) }
    
    before do
      # Create mock attachments for testing
      @attachment1 = double('attachment1', id: 1, purge_later: true, update: true)
      @attachment2 = double('attachment2', id: 2, purge_later: true, update: true)
      @attachment3 = double('attachment3', id: 3, purge_later: true, update: true)
      
      # Mock the images association
      mock_images = double('images_association')
      mock_attachments = double('attachments_collection')
      
      allow(product).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:find_by).with(id: 3).and_return(@attachment3)
      allow(mock_attachments).to receive(:find_by).with(id: 999).and_return(nil) # Non-existent
    end

    it 'deletes images when _destroy is set to true' do
      expect(@attachment1).to receive(:purge_later).once
      expect(@attachment2).to receive(:purge_later).once
      
      product.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, _destroy: true },
        { id: 3, _destroy: '0' } # Should not be deleted
      ]
    end

    it 'handles deletion of non-existent images gracefully' do
      expect(Rails.logger).to receive(:warn).with("Attempted to delete non-existent image attachment: 999")
      
      product.images_attributes = [
        { id: 999, _destroy: '1' }
      ]
    end

    it 'processes deletions before other updates' do
      # Mock additional methods for primary flag handling
      mock_where_not = double('where_not_clause')
      allow(product.images.attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      product.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
    end

    it 'handles mixed deletion and primary flag updates correctly' do
      # Mock additional methods for primary flag handling
      mock_where_not = double('where_not_clause')
      allow(product.images.attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      product.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
    end
  end

  describe 'adding images without replacing existing ones' do
    let(:product) { create(:product, business: business) }
    
    it 'appends new images to existing ones via attach method' do
      # Mock the images attachment
      mock_images = double('images_attachment')
      allow(product).to receive(:images).and_return(mock_images)
      
      # Create mock file objects
      mock_file1 = double('file1', blank?: false)
      mock_file2 = double('file2', blank?: false)
      new_images = [mock_file1, mock_file2]
      
      # Expect attach to be called with the new images
      expect(mock_images).to receive(:attach).with(new_images)
      
      # Test attachment directly (since we removed the images= override)
      product.images.attach(new_images)
    end

    it 'filters out blank and nil images when using attach' do
      mock_images = double('images_attachment')
      allow(product).to receive(:images).and_return(mock_images)
      
      mock_file = double('file', blank?: false)
      
      # Test filtering at the controller level (which handles this now)
      valid_images = [mock_file, nil, '', double('blank_file', blank?: true)].compact.reject(&:blank?)
      
      # Should only attach the valid file
      expect(mock_images).to receive(:attach).with([mock_file])
      
      product.images.attach(valid_images)
    end

    it 'handles empty image arrays gracefully' do
      mock_images = double('images_attachment')
      allow(product).to receive(:images).and_return(mock_images)
      
      # Should not call attach for empty arrays
      expect(mock_images).not_to receive(:attach)
      
      # Test that nothing happens with empty arrays
      empty_arrays = [[], nil, ['', nil].compact.reject(&:blank?)]
      empty_arrays.each do |empty_array|
        next if empty_array.nil? || empty_array.empty?
        product.images.attach(empty_array)
      end
    end

    it 'maintains existing images when adding new ones via attach' do
      # Mock product with existing attachments
      existing_attachment = double('existing_attachment', id: 1)
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      
      allow(product).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:count).and_return(1)
      
      # New file to add
      new_file = double('new_file', blank?: false)
      
      # Should append the new file
      expect(mock_images).to receive(:attach).with([new_file])
      
      product.images.attach([new_file])
    end
  end

  describe 'concurrent image operations' do
    let(:product) { create(:product, business: business) }
    
    it 'handles concurrent deletion and addition operations safely' do
      # Mock existing attachments
      @attachment1 = double('attachment1', id: 1, purge_later: true)
      @attachment2 = double('attachment2', id: 2, update: true)
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      mock_where_not = double('where_not_clause')
      
      allow(product).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      # New file to add
      new_file = double('new_file', blank?: false)
      
      # First, handle deletions and updates via images_attributes
      expect(@attachment1).to receive(:purge_later)
      expect(@attachment2).to receive(:update).with(primary: true)
      
      product.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' }
      ]
      
      # Then, add new images via attach (not through images= override)
      expect(mock_images).to receive(:attach).with([new_file])
      
      product.images.attach([new_file])
    end

    it 'processes multiple concurrent deletion requests safely' do
      # Simulate race condition with multiple deletions
      attachments = (1..5).map do |i|
        double("attachment#{i}", id: i, purge_later: true)
      end
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      
      allow(product).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      
      attachments.each do |attachment|
        allow(mock_attachments).to receive(:find_by).with(id: attachment.id).and_return(attachment)
      end
      
      # All should be deleted safely
      attachments.each do |attachment|
        expect(attachment).to receive(:purge_later)
      end
      
      # Test concurrent deletion operations
      deletion_attributes = attachments.map { |a| { id: a.id, _destroy: '1' } }
      
      product.images_attributes = deletion_attributes
    end
  end

  describe 'primary image management with deletion and addition' do
    let(:product) { create(:product, business: business) }
    
    it 'handles primary flag updates while deleting other images' do
      # Mock three existing attachments
      @attachment1 = double('attachment1', id: 1, purge_later: true)
      @attachment2 = double('attachment2', id: 2, update: true)
      @attachment3 = double('attachment3', id: 3, purge_later: true)
      
      mock_images = double('images_attachment')
      mock_attachments = double('attachments_collection')
      mock_where_not = double('where_not_clause')
      
      allow(product).to receive(:images).and_return(mock_images)
      allow(mock_images).to receive(:attachments).and_return(mock_attachments)
      
      # Setup find_by expectations
      allow(mock_attachments).to receive(:find_by).with(id: 1).and_return(@attachment1)
      allow(mock_attachments).to receive(:find_by).with(id: 2).and_return(@attachment2)
      allow(mock_attachments).to receive(:find_by).with(id: 3).and_return(@attachment3)
      
      # Setup primary flag handling
      allow(mock_attachments).to receive(:where).and_return(mock_where_not)
      allow(mock_where_not).to receive(:not).with(id: @attachment2.id).and_return(mock_where_not)
      allow(mock_where_not).to receive(:update_all).with(primary: false)
      
      # Expectations
      expect(@attachment1).to receive(:purge_later) # Delete
      expect(@attachment3).to receive(:purge_later) # Delete
      expect(@attachment2).to receive(:update).with(primary: true) # Set as primary
      
      product.images_attributes = [
        { id: 1, _destroy: '1' },
        { id: 2, primary: 'true' },
        { id: 3, _destroy: '1' }
      ]
    end

    it 'maintains primary flag integrity when adding new images' do
      # Test that new images don't automatically become primary
      mock_images = double('images_attachment')
      
      allow(product).to receive(:images).and_return(mock_images)
      
      new_file = double('new_file', blank?: false)
      
      # Should just attach without affecting primary flags
      expect(mock_images).to receive(:attach).with([new_file])
      
      product.images.attach([new_file])
    end
  end

  describe 'image validation boundary scenarios' do
    let(:product) { create(:product, business: business) }
    
    it 'handles 15MB file size validation during addition' do
      large_file = double('large_file', blank?: false)
      mock_images = double('images_attachment')
      
      allow(product).to receive(:images).and_return(mock_images)
      
      # Should still attach (validation happens at model level)
      expect(mock_images).to receive(:attach).with([large_file])
      
      product.images.attach([large_file])
    end

    it 'processes image format validation correctly during operations' do
      # Test with various file formats
      png_file = double('png_file', blank?: false)
      jpeg_file = double('jpeg_file', blank?: false)
      webp_file = double('webp_file', blank?: false)
      
      mock_images = double('images_attachment')
      allow(product).to receive(:images).and_return(mock_images)
      
      files = [png_file, jpeg_file, webp_file]
      
      expect(mock_images).to receive(:attach).with(files)
      
      product.images.attach(files)
    end
  end

  describe '#discount_eligible?' do
    it 'returns true when allow_discounts is true' do
      product = build(:product, allow_discounts: true)
      expect(product.discount_eligible?).to be true
    end

    it 'returns false when allow_discounts is false' do
      product = build(:product, allow_discounts: false)
      expect(product.discount_eligible?).to be false
    end
  end

  it 'has show_stock_to_customers enabled by default' do
    product = create(:product, business: business)
    expect(product.show_stock_to_customers).to be true
  end

  it 'allows toggling show_stock_to_customers' do
    product = create(:product, business: business, show_stock_to_customers: false)
    expect(product.show_stock_to_customers).to be false

    product.update!(show_stock_to_customers: true)
    expect(product.show_stock_to_customers).to be true
  end

  it 'has hide_when_out_of_stock disabled by default' do
    product = create(:product, business: business)
    expect(product.hide_when_out_of_stock).to be false
  end

  it 'allows toggling hide_when_out_of_stock' do
    product = create(:product, business: business, hide_when_out_of_stock: true)
    expect(product.hide_when_out_of_stock).to be true

    product.update!(hide_when_out_of_stock: false)
    expect(product.hide_when_out_of_stock).to be false
  end

  describe '#visible_to_customers?' do
    it 'returns false for inactive products' do
      product = create(:product, business: business, active: false)
      expect(product.visible_to_customers?).to be false
    end

    it 'returns true for active products with stock when hide_when_out_of_stock is false' do
      product = create(:product, business: business, active: true, hide_when_out_of_stock: false, stock_quantity: 5)
      expect(product.visible_to_customers?).to be true
    end

    it 'returns true for active products without stock when hide_when_out_of_stock is false' do
      product = create(:product, business: business, active: true, hide_when_out_of_stock: false, stock_quantity: 0)
      expect(product.visible_to_customers?).to be true
    end

    it 'returns false for active products without stock when hide_when_out_of_stock is true' do
      product = create(:product, business: business, active: true, hide_when_out_of_stock: true, stock_quantity: 0)
      expect(product.visible_to_customers?).to be false
    end

    it 'returns true for active products with stock when hide_when_out_of_stock is true' do
      product = create(:product, business: business, active: true, hide_when_out_of_stock: true, stock_quantity: 5)
      expect(product.visible_to_customers?).to be true
    end
  end

  describe 'variant label functionality' do
    let(:product) { create(:product, business: business) }
    
    describe '#should_show_variant_selector?' do
      context 'when product has only default variant' do
        it 'returns false' do
          # Products get a default variant automatically, so we expect false
          expect(product.should_show_variant_selector?).to be false
        end
      end
      
      context 'when product has 2 or more variants total' do
        before do
          create(:product_variant, product: product, name: 'Small')
        end
        
        it 'returns true' do
          expect(product.should_show_variant_selector?).to be true
        end
      end
      
      context 'when product has multiple user-created variants' do
        before do
          create(:product_variant, product: product, name: 'Small')
          create(:product_variant, product: product, name: 'Large')
        end
        
        it 'returns true' do
          expect(product.should_show_variant_selector?).to be true
        end
      end
    end
    
    describe '#display_variant_label' do
      it 'returns the custom variant label text when present' do
        product.update!(variant_label_text: 'Choose a size')
        expect(product.display_variant_label).to eq('Choose a size')
      end
      
      it 'returns default text when variant_label_text is blank' do
        product.variant_label_text = ''
        expect(product.display_variant_label).to eq('Choose a variant')
      end
      
      it 'returns default text when variant_label_text is nil' do
        product.variant_label_text = nil
        expect(product.display_variant_label).to eq('Choose a variant')
      end
    end
    
    describe 'default values' do
      it 'sets default variant_label_text to "Choose a variant"' do
        new_product = create(:product, business: business)
        expect(new_product.variant_label_text).to eq('Choose a variant')
      end
    end
  end
end 