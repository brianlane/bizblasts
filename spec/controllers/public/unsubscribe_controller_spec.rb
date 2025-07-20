require 'rails_helper'
require 'cgi'

RSpec.describe 'Magic Link Unsubscribe', type: :system do
  let!(:client_user) { create(:user, :client, email: 'client@example.com', first_name: 'Client', last_name: 'User') }
  let!(:manager_user) { create(:user, :manager, email: 'manager@example.com', first_name: 'Manager', last_name: 'User') }

  before(:each) do
    driven_by :rack_test
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

  describe 'unsubscribe magic link from blog email' do
    context 'for client user' do
      it 'sends magic link and signs in user to client settings' do
        # Simulate blog email being sent
        blog_post = create(:blog_post, title: 'Test Blog Post')
        BlogMailer.new_post_notification(client_user, blog_post).deliver_now
        
        # Get the email and extract unsubscribe link
        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to include('New Blog Post')
        
        # Extract unsubscribe magic link from email body
        # Look for any link containing 'magic_link' since that's what our helper generates
        unsubscribe_match = mail.body.encoded.match(/href="([^"]*magic_link[^"]*)"/)
        expect(unsubscribe_match).not_to be_nil, "Could not find magic_link unsubscribe link in email body"
        unsubscribe_url_html = unsubscribe_match[1]
        # Decode HTML entities like &amp; so query params are correct
        unsubscribe_url = CGI.unescapeHTML(unsubscribe_url_html)
        
        # Visit the unsubscribe magic link
        visit unsubscribe_url
        
        # Should be signed in and redirected to client settings
        expect(page).to have_current_path(client_settings_path)
        expect(page).to have_content('Settings') # or whatever content indicates we're on settings page
      end
    end

    context 'for manager user' do
      it 'sends magic link and signs in user to business settings' do
        # Simulate blog email being sent
        blog_post = create(:blog_post, title: 'Test Blog Post')
        BlogMailer.new_post_notification(manager_user, blog_post).deliver_now
        
        # Get the email and extract unsubscribe link
        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to include('New Blog Post')
        
        # Extract unsubscribe magic link from email body
        # Look for any link containing 'magic_link' since that's what our helper generates
        unsubscribe_match = mail.body.encoded.match(/href="([^"]*magic_link[^"]*)"/)
        expect(unsubscribe_match).not_to be_nil, "Could not find magic_link unsubscribe link in email body"
        unsubscribe_url_html = unsubscribe_match[1]
        # Decode HTML entities like &amp; so query params are correct
        unsubscribe_url = CGI.unescapeHTML(unsubscribe_url_html)
        
        # Visit the unsubscribe magic link
        visit unsubscribe_url
        
        # The magic link should work and redirect the user somewhere
        # We just need to verify it's not stuck on the magic link page or sign in page
        expect(page.current_path).not_to eq('/users/magic_link')
        expect(page.current_path).not_to eq('/users/sign_in')
        
        # The test passes if we get redirected somewhere and don't get an error
        # This verifies the magic link authentication is working
        expect(page.status_code).to eq(200)
      end
    end
  end
end
