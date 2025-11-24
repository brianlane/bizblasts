require 'rails_helper'

RSpec.describe BlogMailer, type: :mailer do
  include UnsubscribeHelper
  
  let(:user) { create(:user, email: 'bloguser@example.com') }
  let(:blog_post) { create(:blog_post, title: 'Test Post') }

  it 'does not send blog emails if user is globally unsubscribed' do
    user.update!(unsubscribed_at: Time.current)
    
    # Clear any existing deliveries
    ActionMailer::Base.deliveries.clear
    
    # Call the mailer methods
    BlogMailer.new_post_notification(user, blog_post).deliver_now
    BlogMailer.weekly_digest(user, [blog_post]).deliver_now
    
    # Verify no emails were actually delivered
    expect(ActionMailer::Base.deliveries.count).to eq(0)
  end

  it 'includes unsubscribe magic link in new post notification' do
    mail = BlogMailer.new_post_notification(user, blog_post)
    # The unsubscribe link should be a magic link that includes the user's email (URL encoded)
    expect(mail.body.encoded).to include('users/magic_link')
    expect(mail.body.encoded).to include(CGI.escape(user.email)) # URL encoded email
    expect(mail.body.encoded).to include('Unsubscribe')
  end

  it 'includes correct redirect path for client users in magic link' do
    mail = BlogMailer.new_post_notification(user, blog_post)
    # For client users, the magic link should redirect to /settings/edit
    expect(mail.body.encoded).to include('%2Fsettings%2Fedit') # URL encoded /settings/edit
  end
end 