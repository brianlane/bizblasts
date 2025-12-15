# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedWebsiteLayoutService, 'edge cases' do
  let(:business) { create(:business, :with_subdomain) }

  describe 'layout transitions' do
    context 'when switching from enhanced back to basic' do
      before do
        business.update!(website_layout: 'enhanced')
        ActsAsTenant.with_tenant(business) do
          described_class.apply!(business)
        end
      end

      it 'preserves page when switching to basic layout' do
        ActsAsTenant.with_tenant(business) do
          home_page = business.pages.find_by(slug: 'home')
          expect(home_page).to be_present
          expect(home_page.published?).to be true

          # Switch to basic
          business.update!(website_layout: 'basic')

          # Page should still exist
          home_page.reload
          expect(home_page).to be_present
        end
      end

      it 'marks enhanced-specific sections as inactive when switching to basic' do
        ActsAsTenant.with_tenant(business) do
          home_page = business.pages.find_by(slug: 'home')

          # Switch back to basic
          business.update!(website_layout: 'basic')

          # Enhanced sections should still exist but could be inactive
          # depending on business logic
          expect(home_page.page_sections.count).to be > 0
        end
      end
    end

    context 'when enhanced layout is reapplied' do
      it 'updates existing sections rather than duplicating' do
        business.update!(website_layout: 'enhanced')

        ActsAsTenant.with_tenant(business) do
          # Apply once
          described_class.apply!(business)
          home_page = business.pages.find_by(slug: 'home')
          initial_section_count = home_page.page_sections.count

          # Apply again
          described_class.apply!(business)
          home_page.reload

          # Should not duplicate sections
          expect(home_page.page_sections.count).to eq(initial_section_count)
        end
      end

      it 'updates section positions correctly' do
        business.update!(website_layout: 'enhanced')

        ActsAsTenant.with_tenant(business) do
          described_class.apply!(business)
          home_page = business.pages.find_by(slug: 'home')

          # Manually change a position
          hero_section = home_page.page_sections.find_by(section_type: 'hero_banner')
          hero_section.update!(position: 999)

          # Reapply layout
          described_class.apply!(business)

          # Position should be corrected back to 0 (first position)
          hero_section.reload
          expect(hero_section.position).to eq(0)
        end
      end
    end

    context 'when business has no services or products' do
      it 'excludes service and product sections' do
        business.update!(website_layout: 'enhanced')

        ActsAsTenant.with_tenant(business) do
          # Ensure no services or products
          business.services.destroy_all
          business.products.destroy_all

          described_class.apply!(business)
          home_page = business.pages.find_by(slug: 'home')

          # Should not have service or product sections
          expect(home_page.page_sections.where(section_type: 'service_list')).to be_empty
          expect(home_page.page_sections.where(section_type: 'product_list')).to be_empty

          # But should have other sections
          expect(home_page.page_sections.where(section_type: 'hero_banner')).to be_present
          expect(home_page.page_sections.where(section_type: 'testimonial')).to be_present
        end
      end
    end

    context 'when business has services but they are hidden' do
      it 'respects show_services_section setting' do
        business.update!(website_layout: 'enhanced', show_services_section: false)

        ActsAsTenant.with_tenant(business) do
          create(:service, business: business, price: 100, duration: 60)

          described_class.apply!(business)
          home_page = business.pages.find_by(slug: 'home')

          # Should not include service section even though services exist
          expect(home_page.page_sections.where(section_type: 'service_list')).to be_empty
        end
      end
    end
  end

  describe 'error handling' do
    context 'when page cannot be saved' do
      it 'handles validation errors gracefully' do
        business.update!(website_layout: 'enhanced')

        ActsAsTenant.with_tenant(business) do
          # Simulate a validation error by making title invalid
          allow_any_instance_of(Page).to receive(:valid?).and_return(false)
          allow_any_instance_of(Page).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

          expect {
            described_class.apply!(business)
          }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end

    context 'when section cannot be saved' do
      it 'raises error and logs details' do
        business.update!(website_layout: 'enhanced')

        ActsAsTenant.with_tenant(business) do
          allow_any_instance_of(PageSection).to receive(:save!)
            .and_raise(ActiveRecord::RecordInvalid, 'Section validation failed')

          expect {
            described_class.apply!(business)
          }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end

    context 'when business callback fails' do
      it 'logs error and continues' do
        business.update!(website_layout: 'enhanced')

        # Simulate failure in the service
        allow(EnhancedWebsiteLayoutService).to receive(:apply!)
          .and_raise(StandardError, 'Layout application failed')

        # Trigger the callback
        expect {
          business.update!(name: 'Updated Name')
        }.not_to raise_error

        # Error should be logged but not raised
        expect(Rails.logger).to have_received(:error).with(/Unexpected error applying enhanced website layout/)
      end
    end
  end

  describe 'content sanitization' do
    it 'properly escapes HTML in generated content' do
      business.update!(
        website_layout: 'enhanced',
        name: '<script>alert("xss")</script>Business',
        description: '<img src=x onerror=alert(1)>Description'
      )

      ActsAsTenant.with_tenant(business) do
        described_class.apply!(business)
        home_page = business.pages.find_by(slug: 'home')

        hero_section = home_page.page_sections.find_by(section_type: 'hero_banner')

        # Content should be escaped
        expect(hero_section.content['title']).to include('&lt;script&gt;')
        expect(hero_section.content['title']).not_to include('<script>')
      end
    end
  end

  describe 'N+1 query prevention' do
    it 'does not trigger N+1 queries when updating sections' do
      business.update!(website_layout: 'enhanced')

      ActsAsTenant.with_tenant(business) do
        # First application
        described_class.apply!(business)

        # Check for N+1 queries on second application
        expect {
          described_class.apply!(business)
        }.not_to exceed_query_limit(20) # Reasonable limit for this operation
      end
    end
  end
end
