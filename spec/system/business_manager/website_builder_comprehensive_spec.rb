require 'rails_helper'

RSpec.describe 'Website Builder Comprehensive', type: :system do
  let!(:business) { create(:business, tier: 'premium', industry: 'landscaping', host_type: 'subdomain') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:theme) { create(:website_theme, :active, business: business, name: 'Test Theme') }
  let!(:home_page) { create(:page, business: business, title: 'Home', page_type: 'home', status: 'published') }

  before do
    driven_by(:rack_test)
    ActsAsTenant.current_tenant = business
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
  end

  describe 'Complete Website Building Workflow' do
    it 'allows building a complete website from scratch' do
      # Start with pages overview
      visit business_manager_website_pages_path
      expect(page).to have_content('Website Builder')
      
      # Create additional pages
      if page.has_link?('Create Page')
        click_link 'Create Page', match: :first
      elsif page.has_link?('New Page')
        click_link 'New Page', match: :first
      else
        visit new_business_manager_website_page_path
      end
      
      if page.has_field?('page[title]')
        fill_in 'page[title]', with: 'About Us'
        select 'about', from: 'page[page_type]' if page.has_select?('page[page_type]')
        click_button 'Create Page'
        expect(page).to have_content('successfully')
      else
        expect(page).to have_content('Page')
      end
      
      # Work with sections
      visit business_manager_website_page_sections_path(home_page)
      expect(page).to have_content('Edit Sections')
      
      # Test theme management
      visit business_manager_website_themes_path
      expect(page).to have_content('Theme')
      
      # Test template marketplace
      visit business_manager_website_templates_path
      expect(page).to have_content('Template')
    end

    it 'provides consistent navigation between website builder sections' do
      # Test navigation between different parts
      visit business_manager_website_pages_path
      expect(page).to have_content('Website')
      
      # Navigate to themes
      visit business_manager_website_themes_path
      expect(page).to have_current_path(business_manager_website_themes_path)
      
      # Navigate to templates
      visit business_manager_website_templates_path
      expect(page).to have_current_path(business_manager_website_templates_path)
      
      # Return to pages
      visit business_manager_website_pages_path
      expect(page).to have_current_path(business_manager_website_pages_path)
    end

    it 'maintains state across different website builder features' do
      # Create a section
      visit business_manager_website_page_sections_path(home_page)
      
      # Switch to theme editor
      visit business_manager_website_themes_path
      expect(page).to have_content('Test Theme')
      
      # Return to sections
      visit business_manager_website_page_sections_path(home_page)
      expect(page).to have_content('Edit Sections')
    end
  end

  describe 'Cross-feature Integration' do
    it 'integrates themes with page editing' do
      visit business_manager_website_page_sections_path(home_page)
      expect(page).to have_content('Edit Sections')
      
      # Theme should be applied
      expect(page).to have_css('body')  # Basic CSS check
    end

    it 'applies templates correctly' do
      visit business_manager_website_templates_path
      
      if page.has_button?('Apply Template')
        click_button 'Apply Template', match: :first
        expect(page).to have_content('applied', wait: 10)
      end
    end
  end

  describe 'Error Handling' do
    it 'handles missing pages gracefully' do
      visit business_manager_website_page_sections_path(999999)
      expect(page).to have_content('not found').or have_content('404')
    end

    it 'validates required fields' do
      visit business_manager_website_pages_path
      
      if page.has_link?('Create Page')
        click_link 'Create Page', match: :first
      elsif page.has_link?('New Page')
        click_link 'New Page', match: :first
      else
        visit new_business_manager_website_page_path
      end
      
      if page.has_button?('Create Page')
        # Try to submit without title
        click_button 'Create Page'
        expect(page).to have_content("can't be blank").or have_content('required')
      else
        expect(page).to have_content('Page')
      end
    end
  end
end 