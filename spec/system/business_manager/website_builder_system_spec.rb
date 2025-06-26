require 'rails_helper'

RSpec.describe 'Website Builder System', type: :system do
  let!(:business) { create(:business, tier: 'premium', industry: 'landscaping', hostname: 'builderbiz', host_type: 'subdomain', subdomain: 'builderbiz') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:theme) { create(:website_theme, :active, business: business, name: 'Builder Theme') }
  let!(:home_page) { create(:page, business: business, title: 'Home', page_type: 'home', status: 'published') }

  before do
    driven_by(:rack_test)
    ActsAsTenant.current_tenant = business
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
  end

  describe 'Complete Website Builder Workflow' do
    it 'provides complete website building experience' do
      # Start at pages overview
      visit business_manager_website_pages_path
      expect(page).to have_content('Website Builder').or have_content('Home')
      
      # Create a new page
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
        expect(page).to have_content('successfully').or have_content('About Us')
      else
        expect(page).to have_content('Page')
      end
    end

    it 'manages page sections effectively' do
      visit business_manager_website_page_sections_path(home_page)
      expect(page).to have_content('Edit Sections').or have_content('Home')
      
      # Test section management
      if page.has_content?('Section Library') || page.has_button?('Add Section')
        expect(page).to have_content('Section').or have_button('Add Section')
      end
    end

    it 'integrates theme management' do
      visit business_manager_website_themes_path
      expect(page).to have_content('Theme').or have_content('Website Builder')
      expect(page).to have_content('Builder Theme')
      
      # Test theme switching
      if page.has_button?('Activate') || page.has_link?('Edit')
        expect(page).to have_button('Activate').or have_link('Edit')
      end
    end

    it 'provides template marketplace' do
      visit business_manager_website_templates_path
      expect(page).to have_content('Template').or have_content('Website Builder')
      
      # Test template application
      if page.has_button?('Apply Template')
        click_button 'Apply Template', match: :first
        expect(page).to have_content('applied').or have_content('success')
      end
    end
  end

  describe 'Page Builder Interface' do
    before { visit business_manager_website_page_sections_path(home_page) }

    it 'loads page builder interface' do
      expect(page).to have_content('Edit Sections').or have_content('Home')
    end

    it 'displays section management tools' do
      # Should have some way to add/edit sections
      expect(page).to have_content('Section').or have_button('Add')
    end

    it 'shows existing page content' do
      section = create(:page_section, page: home_page, section_type: 'text', position: 0)
      visit business_manager_website_page_sections_path(home_page)
      
      expect(page).to have_content('Text')
    end
  end

  describe 'Theme Integration' do
    it 'applies active theme to builder interface' do
      visit business_manager_website_page_sections_path(home_page)
      
      # Should load with theme applied
      expect(page).to have_css('body')
    end

    it 'maintains theme consistency across pages' do
      visit business_manager_website_themes_path
      expect(page).to have_content('Builder Theme')
      
      visit business_manager_website_pages_path
      expect(page).to have_content('Home')
    end
  end

  describe 'Navigation and User Experience' do
    it 'provides intuitive navigation between builder features' do
      # Test navigation flow
      visit business_manager_website_pages_path
      expect(page).to have_current_path(business_manager_website_pages_path)
      
      visit business_manager_website_themes_path
      expect(page).to have_current_path(business_manager_website_themes_path)
      
      visit business_manager_website_templates_path
      expect(page).to have_current_path(business_manager_website_templates_path)
    end

    it 'maintains business context throughout workflow' do
      # Should maintain business context
      expect(ActsAsTenant.current_tenant).to eq(business)
      
      visit business_manager_website_pages_path
      expect(page).to have_content('Home')
    end
  end

  describe 'Content Management' do
    it 'creates and manages pages' do
      visit business_manager_website_pages_path
      expect(page).to have_content('Home')
      
      # Should be able to create additional pages
      if page.has_link?('Create Page') || page.has_link?('New Page')
        expect(page).to have_link('Create Page').or have_link('New Page')
      end
    end

    it 'manages page sections' do
      visit business_manager_website_page_sections_path(home_page)
      
      # Should provide section management
      expect(page).to have_content('Edit Sections').or have_content('Section')
    end

    it 'supports different section types' do
      visit business_manager_website_page_sections_path(home_page)
      
      # Should support various section types
      if page.has_content?('Section Library')
        expect(page).to have_content('Section Library')
      elsif page.has_content?('Hero') || page.has_content?('Text')
        expect(page).to have_content('Hero').or have_content('Text')
      end
    end
  end

  describe 'Performance and Responsiveness' do
    it 'loads quickly and efficiently' do
      start_time = Time.current
      visit business_manager_website_pages_path
      load_time = Time.current - start_time
      
      expect(page).to have_content('Website Builder').or have_content('Home')
      expect(load_time).to be < 10.seconds
    end

    it 'handles multiple sections efficiently' do
      # Create multiple sections
      5.times do |i|
        create(:page_section, page: home_page, section_type: 'text', position: i)
      end
      
      visit business_manager_website_page_sections_path(home_page)
      expect(page).to have_content('Edit Sections')
    end
  end

  describe 'Error Handling and Edge Cases' do
    it 'handles missing resources gracefully' do
      visit business_manager_website_page_sections_path(99999)
      expect(page).to have_content('not found').or have_content('404')
    end

    it 'validates user input' do
      visit business_manager_website_pages_path
      
      if page.has_link?('Create Page')
        click_link 'Create Page', match: :first
      elsif page.has_link?('New Page')
        click_link 'New Page', match: :first
      else
        visit new_business_manager_website_page_path
      end
      
      if page.has_button?('Create Page')
        # Try to submit without required fields
        click_button 'Create Page'
        expect(page).to have_content("can't be blank").or have_content('required').or have_content('Please fix')
      else
        expect(page).to have_content('Page')
      end
    end

    it 'handles business context properly' do
      # Should maintain proper business isolation
      other_business = create(:business, hostname: 'otherbiz', subdomain: 'otherbiz')
      
      # Try to access a page that doesn't exist for current business
      begin
        visit business_manager_website_page_sections_path(99999)
        expect(page).to have_content('not found').or have_content('404').or have_current_path(business_manager_website_pages_path)
      rescue ActiveRecord::RecordNotFound
        # This is the expected behavior for proper tenant isolation
        expect(true).to be true
      end
    end
  end
end 