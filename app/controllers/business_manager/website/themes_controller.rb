class BusinessManager::Website::ThemesController < BusinessManager::Website::BaseController
  before_action :set_theme, except: [:index, :new, :create]
  
  def index
    @themes = current_business.website_themes.order(:created_at)
    @active_theme = current_business.active_website_theme
  end
  
  def show
    @preview_css = @theme.generate_css_variables
  end
  
  def new
    @theme = current_business.website_themes.build
    @theme.color_scheme = WebsiteTheme::DEFAULT_COLOR_SCHEME
    @theme.typography = WebsiteTheme::DEFAULT_TYPOGRAPHY
    @theme.layout_config = WebsiteTheme::DEFAULT_LAYOUT_CONFIG
  end
  
  def create
    @theme = current_business.website_themes.build(theme_params)
    
    if @theme.save
      redirect_to business_manager_website_theme_path(@theme), 
                  notice: 'Theme was successfully created.'
    else
      render :new
    end
  end
  
  def edit
    @available_fonts = google_fonts_list
    @available_animations = animation_types
  end
  
  def update
    if @theme.update(theme_params)
      respond_to do |format|
        format.html { redirect_to business_manager_website_theme_path(@theme), notice: 'Theme updated successfully' }
        format.json { render json: { status: 'success', css: @theme.generate_css_variables } }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json { render json: { status: 'error', errors: @theme.errors } }
      end
    end
  end
  
  def destroy
    if @theme.active?
      redirect_to business_manager_website_themes_path, 
                  alert: 'Cannot delete the active theme'
      return
    end
    
    @theme.destroy
    redirect_to business_manager_website_themes_path, 
                notice: 'Theme was successfully deleted.'
  end
  
  def activate
    if @theme.activate!
      respond_to do |format|
        format.html { redirect_to business_manager_website_themes_path, notice: 'Theme activated successfully' }
        format.json { render json: { status: 'success', css: @theme.generate_css_variables } }
      end
    else
      respond_to do |format|
        format.html { redirect_to business_manager_website_themes_path, alert: 'Failed to activate theme' }
        format.json { render json: { status: 'error', message: 'Failed to activate theme' } }
      end
    end
  end
  
  def preview
    @preview_theme = @theme
    @sample_page = create_sample_page_data
    
    respond_to do |format|
      format.html { render layout: 'website_preview' }
      format.json { render json: { css: @theme.generate_css_variables, html: render_preview_html } }
    end
  end
  
  def duplicate
    new_theme = @theme.dup
    new_theme.name = "#{@theme.name} (Copy)"
    new_theme.active = false
    
    if new_theme.save
      redirect_to edit_business_manager_website_theme_path(new_theme), 
                  notice: 'Theme duplicated successfully'
    else
      redirect_to business_manager_website_theme_path(@theme), 
                  alert: 'Failed to duplicate theme'
    end
  end
  
  def export
    theme_data = {
      name: @theme.name,
      color_scheme: @theme.color_scheme,
      typography: @theme.typography,
      layout_config: @theme.layout_config,
      custom_css: @theme.custom_css
    }
    
    respond_to do |format|
      format.json { render json: theme_data }
      format.html { 
        send_data theme_data.to_json, 
                  filename: "#{@theme.name.parameterize}.json",
                  type: 'application/json'
      }
    end
  end
  
  def import
    if params[:theme_file].present?
      begin
        theme_data = JSON.parse(params[:theme_file].read)
        
        imported_theme = current_business.website_themes.create!(
          name: "#{theme_data['name']} (Imported)",
          color_scheme: theme_data['color_scheme'],
          typography: theme_data['typography'],
          layout_config: theme_data['layout_config'],
          custom_css: theme_data['custom_css'],
          active: false
        )
        
        redirect_to edit_business_manager_website_theme_path(imported_theme), 
                    notice: 'Theme imported successfully'
      rescue JSON::ParserError
        redirect_to business_manager_website_themes_path, 
                    alert: 'Invalid theme file format'
      rescue => e
        redirect_to business_manager_website_themes_path, 
                    alert: "Failed to import theme: #{e.message}"
      end
    else
      redirect_to business_manager_website_themes_path, 
                  alert: 'Please select a theme file to import'
    end
  end
  
  private
  
  def set_theme
    @theme = current_business.website_themes.find(params[:id])
  end
  
  def theme_params
    params.require(:website_theme).permit(
      :name, :custom_css,
      color_scheme: {},
      typography: {},
      layout_config: {}
    )
  end
  
  def google_fonts_list
    [
      'Inter', 'Roboto', 'Open Sans', 'Lato', 'Montserrat', 'Source Sans Pro',
      'Raleway', 'PT Sans', 'Lora', 'Merriweather', 'Playfair Display',
      'Ubuntu', 'Nunito', 'Oswald', 'Poppins', 'Mukti', 'Rubik'
    ]
  end
  
  def animation_types
    [
      'none', 'fade-in', 'slide-up', 'slide-down', 'slide-left', 'slide-right',
      'zoom-in', 'zoom-out', 'bounce', 'pulse', 'shake'
    ]
  end
  
  def create_sample_page_data
    {
      title: 'Sample Page',
      business_name: current_business.name,
      business_description: current_business.description,
      sections: [
        { type: 'hero_banner', content: "Welcome to #{current_business.name}" },
        { type: 'text', content: current_business.description },
        { type: 'service_list', content: 'Our Services' },
        { type: 'contact_form', content: 'Contact Us' }
      ]
    }
  end
  
  def render_preview_html
    # This would render a simplified preview HTML
    # Implementation depends on how you want to structure the preview
    render_to_string(partial: 'preview_content', locals: { 
      theme: @theme, 
      page_data: @sample_page 
    })
  end

  # Helper method to render sample sections for theme preview
  helper_method :render_sample_section
  
  def render_sample_section(section)
    case section[:type]
    when 'hero_banner'
      %{
        <div class="hero-content text-center">
          <h1 class="text-4xl font-bold text-white mb-4">#{ERB::Util.html_escape(section[:content])}</h1>
          <p class="text-xl text-white mb-8">#{ERB::Util.html_escape(@sample_page[:business_description])}</p>
          <a href="#contact" class="cta-button">Get Started Today</a>
        </div>
      }.html_safe
    when 'text'
      %{
        <div>
          <h2>About #{ERB::Util.html_escape(@sample_page[:business_name])}</h2>
          <p class="text-lg text-gray-600 leading-relaxed">#{ERB::Util.html_escape(@sample_page[:business_description])}</p>
        </div>
      }.html_safe
    when 'service_list'
      services_html = ['Professional Consultation', 'Expert Implementation', 'Ongoing Support'].map do |service|
        %{
          <div class="service-card mb-6">
            <h3>#{ERB::Util.html_escape(service)}</h3>
            <p class="text-gray-600">Professional #{ERB::Util.html_escape(service.downcase)} services tailored to your specific needs and requirements.</p>
          </div>
        }
      end.join
      
      %{
        <div>
          <h2 class="text-center mb-8">#{ERB::Util.html_escape(section[:content])}</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            #{services_html}
          </div>
        </div>
      }.html_safe
    when 'contact_form'
      %{
        <div class="bg-gray-50 p-8 rounded-lg">
          <h2 class="text-center mb-6">#{ERB::Util.html_escape(section[:content])}</h2>
          <div class="max-w-md mx-auto">
            <div class="space-y-4">
              <input type="text" placeholder="Your Name" class="w-full p-3 border border-gray-300 rounded">
              <input type="email" placeholder="Your Email" class="w-full p-3 border border-gray-300 rounded">
              <textarea placeholder="Your Message" rows="4" class="w-full p-3 border border-gray-300 rounded"></textarea>
              <button class="cta-button w-full">Send Message</button>
            </div>
          </div>
        </div>
      }.html_safe
    else
      %{
        <div>
          <h2>#{ERB::Util.html_escape(section[:type].humanize)}</h2>
          <p class="text-gray-600">Sample content for #{ERB::Util.html_escape(@sample_page[:business_name])}.</p>
        </div>
      }.html_safe
    end
  end
end 