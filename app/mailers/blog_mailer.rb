# frozen_string_literal: true

class BlogMailer < ApplicationMailer
  # Send notification email when a new blog post is published
  def new_post_notification(user, blog_post)
    @user = user
    @blog_post = blog_post
    
    mail(
      to: user.email,
      subject: "New Blog Post: #{blog_post.title} - BizBlasts"
    )
  end
  
  # Send weekly digest of blog posts
  def weekly_digest(user, blog_posts)
    @user = user
    @blog_posts = blog_posts
    @week_start = 1.week.ago.beginning_of_week
    @week_end = Date.current.end_of_week
    
    mail(
      to: user.email,
      subject: "BizBlasts Weekly Update - #{@week_start.strftime('%B %d')} to #{@week_end.strftime('%B %d, %Y')}"
    )
  end
end 