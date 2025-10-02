require 'rails_helper'

RSpec.describe 'Sidebar Customization', type: :system do
  include_context 'setup business context'

  before do
    switch_to_subdomain(business.subdomain)
    login_as(manager, scope: :user)
    visit edit_sidebar_business_manager_settings_sidebar_path
  end

  it 'shows all sidebar items and allows reordering and hiding', js: true do
    expect(page).to have_content('Customize Sidebar')
    expect(page).to have_selector('.sidebar-item', minimum: 3)
    # Hide the first item using Capybara's uncheck
    first_label = first('.sidebar-item label')
    sidebar_label = first_label.text
    uncheck first_label[:for]
    # Drag the second item to the top
    sidebar_items = all('.sidebar-item')
    sidebar_items[1].drag_to(sidebar_items[0])
    click_button 'Save Sidebar'
    within('#sidebar') do
      expect(page).not_to have_content(sidebar_label)
    end
  end

  it 'shows all sidebar items in the sidebar when all are visible' do
    # Set all sidebar items to visible for the user
    UserSidebarItem.default_items_for(manager).each_with_index do |item, idx|
      manager.user_sidebar_items.find_or_create_by!(item_key: item[:key]) do |sidebar_item|
        sidebar_item.position = idx
        sidebar_item.visible = true
      end
    end
    visit business_manager_dashboard_path
    sidebar_labels = UserSidebarItem.default_items_for(manager).map { |item| item[:label] }
    within('#sidebar') do
      sidebar_labels.each do |label|
        expect(page).to have_content(label)
      end
    end
  end
end 