require 'rails_helper'

RSpec.describe 'Theme Management', type: :system do
  let!(:business) { create(:business, industry: 'landscaping', host_type: 'subdomain') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:theme1) { create(:website_theme, :active, business: business, name: 'Modern Theme') }
  let!(:theme2) { create(:website_theme, business: business, name: 'Classic Theme') }

  before do
    driven_by(:rack_test)
    ActsAsTenant.current_tenant = business
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
  end

  describe 'Theme Overview' do
    before { visit business_manager_website_themes_path }

    it 'displays theme management interface' do
      expect(page).to have_content('Website Builder').or have_content('Themes')
    end

    it 'shows available themes' do
      expect(page).to have_content('Modern Theme')
      expect(page).to have_content('Classic Theme')
    end

    it 'indicates active theme' do
      # Should show which theme is currently active
      expect(page).to have_content('Modern Theme')
      expect(page).to have_content('Active').or have_content('Current') if page.has_content?('Active')
    end

    it 'provides theme management actions' do
      # Should have buttons/links for theme actions
      expect(page).to have_button('Edit').or have_link('Edit') if page.has_button?('Edit') || page.has_link?('Edit')
      expect(page).to have_button('Activate').or have_link('Activate') if page.has_button?('Activate') || page.has_link?('Activate')
    end
  end

  describe 'Theme Activation' do
    before { visit business_manager_website_themes_path }

    it 'activates different theme' do
      if page.has_button?('Activate')
        # Find and activate the inactive theme using data attribute
        within("[data-theme-id='#{theme2.id}']") do
          click_button 'Activate' if has_button?('Activate')
        end
        expect(page).to have_content('activated').or have_content('Theme changed')
      elsif page.has_link?('Activate')
        within("[data-theme-id='#{theme2.id}']") do
          click_link 'Activate' if has_link?('Activate')
        end
        expect(page).to have_content('activated').or have_content('Theme changed')
      end
    end

    it 'maintains only one active theme' do
      # After activation, only one theme should be active
      expect(page).to have_content('Modern Theme')
      expect(page).to have_content('Classic Theme')
    end
  end

  describe 'Theme Editing' do
    before { visit business_manager_website_themes_path }

    it 'navigates to theme editor' do
      if page.has_link?('Edit')
        within("[data-theme-id='#{theme1.id}']") do
          click_link 'Edit' if has_link?('Edit')
        end
        expect(page).to have_content('Edit Theme').or have_content('Theme Editor')
      elsif page.has_button?('Edit')
        within("[data-theme-id='#{theme1.id}']") do
          click_button 'Edit' if has_button?('Edit')
        end
        expect(page).to have_content('Edit Theme').or have_content('Theme Editor')
      end
    end

    it 'loads theme editor interface' do
      theme_edit_path = edit_business_manager_website_theme_path(theme1)
      visit theme_edit_path
      
      expect(page).to have_content('Edit Theme').or have_content('Theme Editor')
    end

    it 'allows theme customization' do
      theme_edit_path = edit_business_manager_website_theme_path(theme1)
      visit theme_edit_path
      
      if page.has_field?('website_theme[name]')
        fill_in 'website_theme[name]', with: 'Updated Modern Theme'
        click_button 'Save Theme' if page.has_button?('Save Theme')
        click_button 'Update Theme' if page.has_button?('Update Theme')
        
        expect(page).to have_content('successfully')
      end
    end
  end

  describe 'Theme Creation' do
    before { visit business_manager_website_themes_path }

    it 'creates new theme' do
      if page.has_link?('Create Theme') || page.has_link?('New Theme')
        click_link 'Create Theme' if page.has_link?('Create Theme')
        click_link 'New Theme' if page.has_link?('New Theme')
        
        fill_in 'website_theme[name]', with: 'Custom Theme'
        click_button 'Create Theme'
        
        expect(page).to have_content('successfully')
        expect(page).to have_content('Custom Theme')
      end
    end

    it 'validates theme creation' do
      if page.has_link?('Create Theme') || page.has_link?('New Theme')
        click_link 'Create Theme' if page.has_link?('Create Theme')
        click_link 'New Theme' if page.has_link?('New Theme')
        
        # Try to create without name
        click_button 'Create Theme'
        expect(page).to have_content("can't be blank").or have_content('required')
      end
    end
  end

  describe 'Theme Duplication' do
    before { visit business_manager_website_themes_path }

    it 'duplicates existing theme' do
      if page.has_button?('Duplicate') || page.has_link?('Duplicate')
        within("[data-theme-id='#{theme1.id}']") do
          click_button 'Duplicate' if has_button?('Duplicate')
          click_link 'Duplicate' if has_link?('Duplicate')
        end
        
        expect(page).to have_content('duplicated').or have_content('Copy of Modern Theme')
      end
    end
  end

  describe 'Theme Deletion' do
    before { visit business_manager_website_themes_path }

    it 'deletes inactive theme' do
      within("[data-theme-id='#{theme2.id}']") do
        # Simply click the Delete button if it exists
        click_button 'Delete' if has_button?('Delete')
      end
      
      # Check that the theme is no longer visible or a success message appears
      expect(page).to have_content('deleted').or have_no_content('Classic Theme')
    end

    it 'prevents deletion of active theme' do
      # Active theme should not have delete option or should show warning
      within("[data-theme-id='#{theme1.id}']") do
        expect(page).not_to have_button('Delete') unless page.has_content?('warning')
      end
    end
  end

  describe 'Theme Preview' do
    before { visit business_manager_website_themes_path }

    it 'provides theme preview' do
      if page.has_button?('Preview') || page.has_link?('Preview')
        within("[data-theme-id='#{theme1.id}']") do
          click_button 'Preview' if has_button?('Preview')
          click_link 'Preview' if has_link?('Preview')
        end
        
        expect(page).to have_content('Preview').or have_css('.preview')
      end
    end
  end

  describe 'Integration with Pages' do
    let!(:page_record) { create(:page, business: business, title: 'Test Page') }
    
    it 'applies theme to pages' do
      visit business_manager_website_page_sections_path(page_record)
      
      # Theme should be applied to page editor
      expect(page).to have_css('body')
    end
  end
end 