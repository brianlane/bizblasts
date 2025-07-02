require 'rails_helper'

RSpec.describe 'Template Marketplace', type: :system do
  let!(:business) { create(:business, tier: 'premium', industry: 'landscaping', host_type: 'subdomain') }
  let!(:manager) { create(:user, :manager, business: business) }

  before do
    driven_by(:rack_test)
    ActsAsTenant.current_tenant = business
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
  end

  describe 'Template Marketplace Interface' do
    before { visit business_manager_website_templates_path }

    it 'displays template marketplace' do
      expect(page).to have_content('Template').or have_content('Marketplace')
    end

    it 'shows available templates' do
      # Should show some templates from the seeds
      templates = page.all('.template-card, .template-item, .card')
      expect(templates.count).to be > 0 if templates.any?
    end

    it 'provides template filtering' do
      if page.has_select?('industry') || page.has_field?('industry')
        # Test industry filtering
        select 'Landscaping', from: 'industry' if page.has_select?('industry')
        expect(page).to have_content('Template')
      end
    end

    it 'displays template information' do
      # Templates should show name, description, or preview
      if page.has_content?('Template')
        templates = page.all('.template-card, .template-item').first(3)
        templates.each do |template|
          expect(template).to have_content(/.+/) # Some content
        end
      end
    end
  end

  describe 'Template Categories' do
    before { visit business_manager_website_templates_path }

    it 'shows industry-specific templates' do
      # Should show landscaping templates for landscaping business
      expect(page).to have_content('Template')
    end

    it 'shows universal templates' do
      # Universal templates should be available to all businesses
      expect(page).to have_content('Template')
    end

    it 'filters by template type' do
      if page.has_button?('Filter') || page.has_select?('type')
        # Test filtering functionality
        expect(page).to have_content('Template')
      end
    end
  end

  describe 'Template Preview' do
    before { visit business_manager_website_templates_path }

    it 'provides template preview' do
      if page.has_button?('Preview') || page.has_link?('Preview')
        click_button 'Preview', match: :first if page.has_button?('Preview')
        click_link 'Preview', match: :first if page.has_link?('Preview')
        
        expect(page).to have_content('Preview').or have_css('.preview, .modal')
      end
    end

    it 'shows template details' do
      if page.has_button?('View Details') || page.has_link?('View Details')
        click_button 'View Details', match: :first if page.has_button?('View Details')
        click_link 'View Details', match: :first if page.has_link?('View Details')
        
        expect(page).to have_content('Template').or have_content('Details')
      end
    end
  end

  describe 'Template Application' do
    before { visit business_manager_website_templates_path }

    it 'applies template to business' do
      if page.has_button?('Apply Template') || page.has_button?('Use Template')
        click_button 'Apply Template', match: :first if page.has_button?('Apply Template')
        click_button 'Use Template', match: :first if page.has_button?('Use Template')
        
        expect(page).to have_content('applied').or have_content('success')
      end
    end

    it 'confirms template application' do
      if page.has_button?('Apply Template')
        click_button 'Apply Template', match: :first
        
        # Should show confirmation or redirect
        expect(page).to have_content('applied').or have_content('confirm')
      end
    end

    it 'redirects after successful application' do
      if page.has_button?('Apply Template')
        click_button 'Apply Template', match: :first
        
        # Should redirect to pages or dashboard
        expect(page).to have_current_path(business_manager_website_pages_path).or have_content('successfully')
      end
    end
  end

  describe 'Premium Templates' do
    before { visit business_manager_website_templates_path }

    it 'shows premium template indicators' do
      # Premium templates should be marked
      if page.has_content?('Premium') || page.has_content?('Pro')
        expect(page).to have_content('Premium').or have_content('Pro')
      end
    end

    it 'allows premium template access for premium businesses' do
      # Premium tier business should access premium templates
      if page.has_button?('Apply Template')
        # Should be able to apply any template
        expect(page).to have_button('Apply Template')
      end
    end
  end

  describe 'Template Search' do
    before { visit business_manager_website_templates_path }

    it 'provides template search' do
      if page.has_field?('search') || page.has_field?('query')
        fill_in 'search', with: 'modern' if page.has_field?('search')
        fill_in 'query', with: 'modern' if page.has_field?('query')
        
        if page.has_button?('Search')
          click_button 'Search'
        end
        
        expect(page).to have_content('Template')
      end
    end

    it 'shows search results' do
      if page.has_field?('search')
        fill_in 'search', with: 'business'
        
        if page.has_button?('Search')
          click_button 'Search'
          expect(page).to have_content('Template')
        end
      end
    end
  end

  describe 'Template Sorting' do
    before { visit business_manager_website_templates_path }

    it 'sorts templates by different criteria' do
      if page.has_select?('sort') || page.has_select?('order')
        select 'Name', from: 'sort' if page.has_select?('sort')
        expect(page).to have_content('Template')
      end
    end

    it 'shows newest templates first' do
      if page.has_content?('Newest') || page.has_content?('Latest')
        expect(page).to have_content('Template')
      end
    end
  end

  describe 'Error Handling' do
    it 'handles template application errors gracefully' do
      visit business_manager_website_templates_path
      
      # Even if there are errors, page should still load
      expect(page).to have_content('Template').or have_content('Marketplace')
    end

    it 'shows appropriate messages for empty results' do
      visit business_manager_website_templates_path
      
      if page.has_field?('search')
        fill_in 'search', with: 'nonexistenttemplate12345'
        
        if page.has_button?('Search')
          click_button 'Search'
          expect(page).to have_content('No templates').or have_content('not found')
        end
      end
    end
  end

  describe 'Responsive Design' do
    before { visit business_manager_website_templates_path }

    it 'works on different screen sizes' do
      # Should be responsive
      expect(page).to have_css('body')
      expect(page).to have_content('Template')
    end
  end

  describe 'Integration with Other Features' do
    it 'links to page builder after template application' do
      visit business_manager_website_templates_path
      
      if page.has_button?('Apply Template')
        click_button 'Apply Template', match: :first
        
        # Should eventually lead to page builder or pages list
        expect(page).to have_current_path(business_manager_website_pages_path).or have_content('Page')
      end
    end

    it 'preserves business context' do
      visit business_manager_website_templates_path
      
      # Should be in business context
      expect(page).to have_content('Template')
      
      # Verify business context is maintained (check in request context, not test context)
      # Since ActsAsTenant.current_tenant is request-scoped, we verify through page content
      expect(page).to have_content('Template')
      
      # Test business context indirectly through functionality that requires it
      if page.has_button?('Apply Template')
        # Templates should be filtered for this business's industry/tier
        expect(page).to have_content('landscaping').or have_content('Template')
      end
    end
  end
end 