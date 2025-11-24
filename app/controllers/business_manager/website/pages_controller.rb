class BusinessManager::Website::PagesController < BusinessManager::Website::BaseController
  before_action :set_page, except: [:index, :new, :create, :update_priority]
  
  def index
    sort_param = params[:sort] || 'default'
    @pages = current_business.pages.includes(:page_sections, :page_versions)
    
    @pages = case sort_param
             when 'priority' then @pages.by_priority
             when 'popular' then @pages.popular
             when 'recent' then @pages.recent
             else @pages.order(:page_type, :title)
             end
             
    @published_pages = @pages.published
    @draft_pages = @pages.draft
    @sort_options = [
      ['Default', 'default'],
      ['By Priority', 'priority'],
      ['Most Popular', 'popular'],
      ['Recently Updated', 'recent']
    ]
  end
  
  def show
    @preview_mode = params[:preview] == 'true'
    @page_versions = @page.page_versions.latest.limit(10)
  end
  
  def new
    @page = current_business.pages.build
    @available_page_types = Page.page_types.keys
    
    # Handle quick template autofill
    if params[:template].present?
      apply_template_defaults(@page, params[:template])
    end
  end
  
  def create
    @page = current_business.pages.build(page_params)
    
    if @page.save
      # Create initial version
      PageVersion.create_from_page(@page, current_user, "Initial page creation")
      
      redirect_to edit_business_manager_website_page_path(@page), 
                  notice: 'Page was successfully created.'
    else
      @available_page_types = Page.page_types.keys
      flash.now[:alert] = 'Please fix the errors below to create the page.'
      render :new, status: :unprocessable_content
    end
  end
  
  def edit
    @available_sections = section_types_for_tier
    @page_versions = @page.page_versions.latest.limit(10)
    @current_sections = @page.page_sections.ordered
  end
  
  def update
    if @page.update(page_params)
      # Create version snapshot
      create_version_snapshot("Page updated")
      
      respond_to do |format|
        format.html { redirect_to business_manager_website_page_path(@page), notice: 'Page updated successfully' }
        format.json { render json: { status: 'success', message: 'Page updated' } }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json { render json: { status: 'error', errors: @page.errors } }
      end
    end
  end
  
  def destroy
    @page.destroy
    redirect_to business_manager_website_pages_path, 
                notice: 'Page was successfully deleted.'
  end
  
  def preview
    @preview_mode = true
    @business = current_business
    render layout: 'website_preview'
  end
  
  def publish
    if @page.publish!
      redirect_to business_manager_website_page_path(@page), 
                  notice: 'Page published successfully'
    else
      redirect_to business_manager_website_page_path(@page), 
                  alert: 'Failed to publish page'
    end
  end
  
  def create_version
    version = @page.create_draft_version!(current_user, params[:notes])
    
    respond_to do |format|
      format.json { render json: { status: 'success', version: version.version_number } }
    end
  end
  
  def restore_version
    version = @page.page_versions.find(params[:version_id])
    
    if version.restore_to_page!
      redirect_to edit_business_manager_website_page_path(@page), 
                  notice: "Restored to version #{version.version_number}"
    else
      redirect_to edit_business_manager_website_page_path(@page), 
                  alert: 'Failed to restore version'
    end
  end
  
  def duplicate
    new_page = @page.dup
    new_page.title = "#{@page.title} (Copy)"
    new_page.slug = "#{@page.slug}-copy"
    new_page.status = :draft
    new_page.published_at = nil
    new_page.view_count = 0
    new_page.priority = 0
    
    if new_page.save
      # Duplicate sections
      @page.page_sections.each do |section|
        new_section = section.dup
        new_section.page = new_page
        new_section.save
      end
      
      # Create initial version
      PageVersion.create_from_page(new_page, current_user, "Duplicated from #{@page.title}")
      
      redirect_to edit_business_manager_website_page_path(new_page), 
                  notice: 'Page duplicated successfully'
    else
      redirect_to business_manager_website_page_path(@page), 
                  alert: 'Failed to duplicate page'
    end
  end
  
  def update_priority
    page_ids = params[:page_ids] || []
    
    page_ids.each_with_index do |page_id, index|
      current_business.pages.where(id: page_id).update_all(priority: page_ids.length - index)
    end
    
    respond_to do |format|
      format.json { render json: { status: 'success', message: 'Page order updated' } }
    end
  end
  
  def track_view
    @page.increment_view_count!
    
    respond_to do |format|
      format.json { render json: { status: 'success', view_count: @page.view_count } }
    end
  end
  
  private
  
  def set_page
    @page = current_business.pages.find(params[:id])
  end
  
  def page_params
    params.require(:page).permit(
      :title, :slug, :page_type, :meta_description, :seo_title, :seo_keywords,
      :show_in_menu, :menu_order, :content, :custom_theme_settings, :status
    )
  end
  
  def create_version_snapshot(notes = nil)
    @page.create_draft_version!(current_user, notes)
  end
  
  def section_types_for_tier
            basic_sections = %w[header text image contact_form service_list product_list]
    standard_sections = %w[gallery testimonial cta hero_banner]
    premium_sections = %w[product_grid team_showcase pricing_table faq_section 
                         social_media video_embed map_location newsletter_signup]
    
    sections = basic_sections
    sections += standard_sections if current_business.standard_tier? || current_business.premium_tier?
    sections += premium_sections if current_business.premium_tier?
    
    sections
  end
  
  def apply_template_defaults(page, template)
    case template
    when 'about_us'
      page.title = 'About Us'
      page.page_type = 'about'
      page.slug = 'about'
      page.meta_description = 'Learn more about our company, mission, and team.'
      page.seo_title = 'About Us - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 2
    when 'services'
      page.title = 'Our Services'
      page.page_type = 'services'
      page.slug = 'services'
      page.meta_description = 'Explore our comprehensive range of professional services.'
      page.seo_title = 'Services - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 3
    when 'portfolio'
      page.title = 'Portfolio'
      page.page_type = 'portfolio'
      page.slug = 'portfolio'
      page.meta_description = 'View our portfolio of completed projects and success stories.'
      page.seo_title = 'Portfolio - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 4
    when 'team'
      page.title = 'Our Team'
      page.page_type = 'team'
      page.slug = 'team'
      page.meta_description = 'Meet our talented team of professionals.'
      page.seo_title = 'Our Team - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 5
    when 'pricing'
      page.title = 'Pricing'
      page.page_type = 'pricing'
      page.slug = 'pricing'
      page.meta_description = 'View our competitive pricing and service packages.'
      page.seo_title = 'Pricing - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 6
    when 'contact'
      page.title = 'Contact Us'
      page.page_type = 'contact'
      page.slug = 'contact'
      page.meta_description = 'Get in touch with us for inquiries and support.'
      page.seo_title = 'Contact Us - ' + current_business.name
      page.show_in_menu = true
      page.menu_order = 7
    end
  end
end 