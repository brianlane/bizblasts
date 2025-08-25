# frozen_string_literal: true

class BlogMailer < ApplicationMailer
  # Send notification email when a new blog post is published
  def new_post_notification(user, blog_post)
    return unless user.can_receive_email?(:blog)
    @user = user
    set_unsubscribe_token(user)
    @blog_post = blog_post
    # For manager or staff recipients, capture their business to build tenant-specific URLs in templates
    @business = user.business if user.manager? || user.staff?
    
    mail(
      to: user.email,
      subject: "New Blog Post: #{blog_post.title} - BizBlasts",
      reply_to: @support_email
    )
  end
  
  # Send weekly digest of blog posts
  def weekly_digest(user, blog_posts)
    return unless user.can_receive_email?(:blog)
    @user = user
    set_unsubscribe_token(user)
    @blog_posts = blog_posts
    @week_start = 1.week.ago.beginning_of_week
    @week_end = Date.current.end_of_week
    # Provide business context for manager or staff recipients so views can generate correct subdomain links
    @business = user.business if user.manager? || user.staff?
    
    mail(
      to: user.email,
      subject: "BizBlasts Weekly Update - #{@week_start.strftime('%B %d')} to #{@week_end.strftime('%B %d, %Y')}",
      reply_to: @support_email
    )
  end
end 