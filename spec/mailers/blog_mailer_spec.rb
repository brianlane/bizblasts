require 'rails_helper'

RSpec.describe BlogMailer, type: :mailer do
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

  it 'includes unsubscribe link in new post notification' do
    mail = BlogMailer.new_post_notification(user, blog_post)
    unsubscribe_link = unsubscribe_url(token: user.unsubscribe_token)
    expect(mail.body.encoded).to include(unsubscribe_link)
  end

  it 'includes manage email preferences link in new post notification' do
    mail = BlogMailer.new_post_notification(user, blog_post)
    expect(mail.body.encoded).to include(edit_client_settings_url)
  end
end 