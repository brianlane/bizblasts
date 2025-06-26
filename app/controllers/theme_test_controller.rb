class ThemeTestController < ApplicationController
  before_action :set_business_and_theme
  
  def index
    # Simple theme test page - no authentication required for development
    @current_theme = @theme || default_theme_data
    @business = @current_business
  end

  def preview
    # Preview a specific theme
    if params[:theme_id].present?
      @theme = WebsiteTheme.find(params[:theme_id])
      @current_theme = @theme
    elsif params[:business_subdomain].present?
      business = Business.find_by(subdomain: params[:business_subdomain])
      @theme = business&.active_website_theme
      @current_theme = @theme || default_theme_data
      @business = business
    end
    
    render :index
  end

  private

  def set_business_and_theme
    # Check if we're on a business subdomain
    if request.subdomain.present? && request.subdomain != 'www'
      @current_business = Business.find_by(subdomain: request.subdomain)
      @theme = @current_business&.active_website_theme
    end
  end

  def default_theme_data
    # Fallback theme data for when no theme is active
    OpenStruct.new(
      color_scheme: WebsiteTheme::DEFAULT_COLOR_SCHEME,
      typography: WebsiteTheme::DEFAULT_TYPOGRAPHY,
      layout_config: WebsiteTheme::DEFAULT_LAYOUT_CONFIG,
      generate_css_variables: -> { 
        ":root {\n" + 
        WebsiteTheme::DEFAULT_COLOR_SCHEME.map { |k, v| "  --color-#{k.to_s.gsub('_', '-')}: #{v};" }.join("\n") +
        "\n}"
      }
    )
  end
end 