require 'rails_helper'

RSpec.describe EnhancedWebsiteLayoutService, type: :service do
  let(:business) { create(:business, :free_tier, show_services_section: true, show_products_section: true) }

  before do
    business.update!(website_layout: 'enhanced')
  end

  describe '.apply!' do
    context 'with services and products' do
      let!(:service) { create(:service, business: business, name: 'Premium Detail') }
      let!(:product) { create(:product, business: business, name: 'Ceramic Kit') }

      it 'creates a published home page with enhanced sections' do
        business.pages.destroy_all

        expect do
          described_class.apply!(business)
        end.to change { business.pages.count }.by(1)

        home_page = business.pages.find_by(slug: 'home')
        expect(home_page).to be_present
        expect(home_page).to be_published
        expect(home_page.page_sections.pluck(:section_type)).to include(
          'hero_banner', 'text', 'service_list', 'product_list', 'testimonial', 'newsletter_signup', 'social_media'
        )
      end

      it 'updates existing enhanced page without duplicating sections' do
        business.pages.destroy_all
        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')
        original_ids = home_page.page_sections.order(:position).pluck(:id)

        expect do
          described_class.apply!(business)
          home_page.reload
        end.not_to change { home_page.page_sections.count }

        expect(home_page.page_sections.order(:position).pluck(:id)).to match_array(original_ids)
      end
    end

    context 'without services' do
      let!(:product) { create(:product, business: business) }

      it 'skips the service section' do
        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')
        expect(home_page.page_sections.pluck(:section_type)).not_to include('service_list')
      end
    end

    context 'without products' do
      let!(:service) { create(:service, business: business, name: 'Premium Detail') }

      it 'skips the product section' do
        business.products.destroy_all
        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')
        expect(home_page.page_sections.pluck(:section_type)).not_to include('product_list')
      end
    end

    context 'with gallery enabled' do
      let!(:service) { create(:service, business: business, name: 'Premium Detail') }

      before do
        business.update!(gallery_enabled: true, show_gallery_section: true)
      end

      it 'returns gallery_layout as a string when set to a symbol enum value' do
        business.update!(gallery_layout: :masonry)
        create(:gallery_photo, business: business)

        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')
        gallery_section = home_page.page_sections.find_by(section_type: 'gallery')

        expect(gallery_section).to be_present
        expect(gallery_section.section_config['layout']).to eq('masonry')
        expect(gallery_section.section_config['layout']).to be_a(String)
      end

      it 'returns gallery_layout as a string when using default value' do
        # gallery_layout defaults to :grid (0) via database default
        business.update!(gallery_layout: :grid)
        create(:gallery_photo, business: business)

        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')
        gallery_section = home_page.page_sections.find_by(section_type: 'gallery')

        expect(gallery_section).to be_present
        expect(gallery_section.section_config['layout']).to eq('grid')
        expect(gallery_section.section_config['layout']).to be_a(String)
      end

      it 'ensures type consistency between different gallery_layout values' do
        # Test that all enum values return strings consistently
        %i[grid masonry carousel].each do |layout|
          business.update!(gallery_layout: layout)
          business.pages.destroy_all
          create(:gallery_photo, business: business) unless business.gallery_photos.any?

          described_class.apply!(business)
          home_page = business.pages.find_by(slug: 'home')
          gallery_section = home_page.page_sections.find_by(section_type: 'gallery')

          expect(gallery_section.section_config['layout']).to be_a(String)
          expect(gallery_section.section_config['layout']).to eq(layout.to_s)
        end
      end
    end
  end
end

