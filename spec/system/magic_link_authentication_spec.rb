# frozen_string_literal: true

require 'rails_helper'
require 'uri'
require 'cgi'

RSpec.describe 'Magic Link Authentication', type: :system do
  let!(:user) { create(:user, :client, email: 'magic@example.com', first_name: 'Magic', last_name: 'User') }

  before(:each) do    
    # Configure Capybara to use lvh.me
    Capybara.configure do |config|
      config.default_host = "http://lvh.me:#{Capybara.server_port}"
      config.app_host     = "http://lvh.me:#{Capybara.server_port}"
    end
    # Override mailer URL options to match test server
    ActionMailer::Base.default_url_options = { host: 'lvh.me', port: Capybara.server_port }
    ActionMailer::Base.deliveries.clear
  end

  after(:each) do
    # Reset mailer URL options
    ActionMailer::Base.default_url_options = {}
  end

  describe 'requesting a magic link' do
    before do
      visit new_user_session_path
      click_link 'Sign in with magic link'
    end

    it 'shows the magic link form' do
      expect(page).to have_content('Sign in with a magic link')
    end

    it 'sends the magic link email' do
      fill_in 'Email', with: user.email
      click_button 'Send magic link'

      expect(page).to have_content('A login link has been sent to your email address')
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.subject).to eq('Your BizBlasts login link')
    end
  end

  describe 'using the magic link' do
    before do
      visit new_user_session_path
      click_link 'Sign in with magic link'
      fill_in 'Email', with: user.email
      click_button 'Send magic link'

      mail = ActionMailer::Base.deliveries.last
      url_html = mail.body.encoded.match(%r{http[s]?:\/\/[^\"]+})[0]
      # Decode HTML entities like &amp; so query params are correct
      url = CGI.unescapeHTML(url_html)
      visit url
    end

    it 'signs in the user successfully' do
      expect(page).to have_content('Signed in successfully.')
    end
  end
end
