class BlogController < ApplicationController
  # Skip authentication for blog pages
  skip_before_action :authenticate_user!, only: [:index, :show, :feed]
  # Skip tenant setting for blog since it's on the main domain
  skip_before_action :set_tenant, only: [:index, :show, :feed]

  before_action :set_blog_post, only: [:show]

  def index
    @blog_posts = BlogPost.published.recent
    @blog_posts = @blog_posts.by_category(params[:category]) if params[:category].present?
    @blog_posts = @blog_posts.page(params[:page]).per(10)
    
    @categories = BlogPost.published.distinct.pluck(:category).compact.sort
    @featured_posts = BlogPost.published.recent.limit(3)
  end

  def show
    # Blog post is already loaded by set_blog_post
    # No need for redirect since routes ensure canonical URL format
  end

  def feed
    @blog_posts = BlogPost.published.recent.limit(20)
    
    respond_to do |format|
      format.xml { render 'feed', layout: false }
    end
  end

  private

  def set_blog_post
    if params[:year] && params[:month] && params[:day] && params[:slug]
      # Date-based URL format: /blog/2025/01/15/slug
      date_str = "#{params[:year]}-#{params[:month].rjust(2, '0')}-#{params[:day].rjust(2, '0')}"
      date = Date.parse(date_str)
      @blog_post = BlogPost.published.where(slug: params[:slug])
                           .where('DATE(published_at) = ?', date)
                           .first!
    else
      # Fallback for direct slug access
      @blog_post = BlogPost.published.find_by!(slug: params[:id] || params[:slug])
    end
  rescue Date::Error, ActiveRecord::RecordNotFound
    raise ActionController::RoutingError, 'Blog post not found'
  end
end 