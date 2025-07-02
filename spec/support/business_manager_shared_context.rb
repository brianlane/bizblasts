# frozen_string_literal: true

RSpec.shared_context 'setup business context' do
  let!(:business)    { FactoryBot.create(:business) }
  let!(:manager)     { FactoryBot.create(:user, :manager, business: business) }
  let!(:staff_user)  { FactoryBot.create(:user, :staff, business: business) }
  let!(:staff_member){ FactoryBot.create(:staff_member, business: business, user: staff_user, name: "#{staff_user.first_name} #{staff_user.last_name}") }
  let!(:service1)    { FactoryBot.create(:service, business: business, name: 'Waxing') }
  let!(:service2)    { FactoryBot.create(:service, business: business, name: 'Massage') }

  let!(:other_business){ FactoryBot.create(:business, subdomain: 'otherbiz') }
  let!(:other_user)   { FactoryBot.create(:user, :manager, business: other_business) }

  def switch_to_subdomain(subdomain)
    Capybara.app_host = "http://#{subdomain}.lvh.me"
    # Optionally set server host/port if needed for rack_test
    # Capybara.server_host = 'lvh.me'
  end

  before do
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end
end 