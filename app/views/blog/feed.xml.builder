xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title "BizBlasts Blog"
    xml.description "Latest updates, features, and business tips from BizBlasts - the platform for service businesses"
    xml.link blog_url
    xml.language "en-us"
    xml.lastBuildDate @blog_posts.first&.published_at&.rfc822

    @blog_posts.each do |post|
      xml.item do
        xml.title post.title
        xml.description post.excerpt
        xml.pubDate post.published_at.rfc822
        xml.link root_url.chomp('/') + post.url_path
        xml.guid root_url.chomp('/') + post.url_path, isPermaLink: true
        xml.category post.category_display_name if post.category.present?
        xml.author "#{post.author_email} (#{post.author_name})" if post.author_name.present?
      end
    end
  end
end 