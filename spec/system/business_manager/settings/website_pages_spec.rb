require 'rails_helper'

RSpec.describe "Website Pages Settings", type: :system do
  # Reuse the shared context for setting up a business and manager
  include_context 'setup business context'

  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  it "shows and updates website pages settings" do
    visit edit_business_manager_settings_website_pages_path

    # Initial defaults
    expect(page).to have_field('Basic layout (current business landing page)', checked: true)
    expect(page).to have_field('Enhanced layout (immersive homepage with your same content)', checked: false)
    expect(page).to have_field('Show Services Section', checked: true)
    expect(page).to have_field('Show Products Section', checked: true)
    expect(page).to have_field('Enable Estimate Page', checked: true)

    # Update settings
    uncheck 'Show Products Section'
    uncheck 'Enable Estimate Page'
    fill_in 'Twitter URL', with: 'https://twitter.com/testbiz'
    choose 'Enhanced layout (immersive homepage with your same content)'

    click_button 'Save Changes'

    expect(page).to have_content('Website pages settings updated.')
    business.reload
    expect(business.show_services_section).to eq true
    expect(business.show_products_section).to eq false
    expect(business.show_estimate_page).to eq false
    expect(business.twitter_url).to eq 'https://twitter.com/testbiz'
    expect(business.website_layout).to eq 'enhanced'

    home_page = business.pages.find_by(slug: 'home')
    expect(home_page).to be_present
    expect(home_page).to be_published
    expect(home_page.page_sections.pluck(:section_type)).to include('hero_banner', 'testimonial', 'social_media')
  end
end 