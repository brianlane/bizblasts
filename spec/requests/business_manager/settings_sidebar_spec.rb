require 'rails_helper'

RSpec.describe 'BusinessManager::Settings sidebar customization', type: :request do
  let!(:business) { create(:business, tier: :standard) }
  let!(:user) { create(:user, :manager, business: business) }
  let(:host_name) { "#{business.hostname}.lvh.me" }

  before do
    host! host_name
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'shows the sidebar customization page' do
    get edit_sidebar_business_manager_settings_path
    expect(response).to be_successful
    expect(response.body).to include('Customize Sidebar')
  end

  it 'updates sidebar order and visibility' do
    patch update_sidebar_business_manager_settings_path, params: {
      sidebar_items: [
        { key: 'dashboard', visible: '1' },
        { key: 'bookings', visible: '0' }
      ]
    }
    expect(response).to redirect_to(business_manager_settings_path)
    user.reload
    # All default sidebar items should be created (18 total)
    expect(user.user_sidebar_items.count).to eq(18)
    # Check that the specified items have correct visibility
    expect(user.user_sidebar_items.find_by(item_key: 'dashboard').visible).to eq(true)
    expect(user.user_sidebar_items.find_by(item_key: 'bookings').visible).to eq(false)
    # Check that other items are set to visible: false (not in submitted params)
    expect(user.user_sidebar_items.find_by(item_key: 'website').visible).to eq(false)
  end

  it 'does not show Website Builder for free tier' do
    business.update!(tier: :free)
    get edit_sidebar_business_manager_settings_path
    expect(response.body).not_to include('Website Builder')
  end

  it 'shows Website Builder for standard tier' do
    business.update!(tier: :standard)
    get edit_sidebar_business_manager_settings_path
    expect(response.body).to include('Website Builder')
  end
end 