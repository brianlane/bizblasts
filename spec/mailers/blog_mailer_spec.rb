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
end 