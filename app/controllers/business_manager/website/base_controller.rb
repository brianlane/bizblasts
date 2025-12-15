class BusinessManager::Website::BaseController < BusinessManager::BaseController
  before_action :ensure_website_theme
  
  protected
  
  def ensure_website_theme
    return if current_business.active_website_theme.present?
    
    # Create default theme if none exists
    WebsiteTemplateService.create_default_theme_for_business(current_business)
  end
  
  def current_theme
    @current_theme ||= current_business.active_website_theme
  end
  helper_method :current_theme
end 