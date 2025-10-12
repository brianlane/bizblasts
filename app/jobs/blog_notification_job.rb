class BlogNotificationJob < ApplicationJob
  queue_as :default

  def perform(blog_post_id)
    blog_post = BlogPost.find_by(id: blog_post_id)
    return unless blog_post&.published?

    Rails.logger.info "[BLOG] Sending email notifications for blog post: #{blog_post.title}"

    # Find all users who have blog notifications enabled
    subscribed_users = User.where(
      "(users.notification_preferences->>'email_blog_updates')::boolean = true OR " +
      "(users.notification_preferences->>'email_promotions')::boolean = true OR " +
      "(users.notification_preferences->>'email_marketing_updates')::boolean = true"
    )

    # Filter by global unsubscribe and granular preferences
    subscribed_users = subscribed_users.select { |u| u.can_receive_email?(:blog) }

    # Send notifications in batches to avoid overwhelming the email service
    subscribed_users.each_slice(50) do |user_batch|
      user_batch.each do |user|
        begin
          BlogMailer.new_post_notification(user, blog_post).deliver_later(queue: 'mailers')
          Rails.logger.info "[BLOG] Scheduled email notification for user: #{user.email}"
        rescue => e
          Rails.logger.error "[BLOG] Failed to schedule email notification for user #{user.email}: #{e.message}"
        end
      end
    end

    Rails.logger.info "[BLOG] Completed scheduling email notifications for blog post: #{blog_post.title}"
  end
end 