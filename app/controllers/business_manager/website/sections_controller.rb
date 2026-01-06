class BusinessManager::Website::SectionsController < BusinessManager::Website::BaseController
  before_action :set_page
  before_action :set_section, except: [:index, :create, :reorder]

  # GET /manage/website/pages/:page_id/sections/:id/manage_gallery
  def manage_gallery
    respond_to do |format|
      format.html {
        render partial: 'gallery_manager',
               locals: { section: @section, page: @page }
      }
    end
  end

  # POST /manage/website/pages/:page_id/sections/:id/gallery/upload_photo
  def upload_photo
    file = params[:photo]
    attributes = params.permit(:title, :description).to_h

    photo = add_photo_to_section(@section, file, attributes)

    respond_to do |format|
      format.json {
        render json: {
          status: 'success',
          photo: photo_json(photo)
        }
      }
    end
  rescue StandardError => e
    respond_to do |format|
      format.json {
        render json: { status: 'error', error: e.message },
               status: :unprocessable_entity
      }
    end
  end

  # DELETE /manage/website/pages/:page_id/sections/:id/gallery/photos/:photo_id
  def remove_photo
    photo = @section.gallery_photos.find(params[:photo_id])
    photo.destroy

    respond_to do |format|
      format.json { render json: { status: 'success' } }
    end
  end

  # POST /manage/website/pages/:page_id/sections/:id/gallery/reorder
  def reorder_photos
    photo_ids = params[:photo_ids] || []

    # Validate that all section photos are included
    all_photo_ids = @section.gallery_photos.pluck(:id).sort
    provided_photo_ids = photo_ids.map(&:to_i).sort

    if all_photo_ids != provided_photo_ids
      respond_to do |format|
        format.json {
          render json: {
            status: 'error',
            error: 'All photos must be included in reorder request'
          }, status: :unprocessable_entity
        }
      end
      return
    end

    # Use a transaction to safely reorder photos
    # First set all to negative positions to avoid uniqueness conflicts,
    # then update to final positions
    ActiveRecord::Base.transaction do
      # Step 1: Set all section photos to negative temporary positions
      @section.gallery_photos.update_all("position = -position - 1000000")

      # Step 2: Update to final positions
      photo_ids.each_with_index do |photo_id, index|
        @section.gallery_photos.find(photo_id).update_column(:position, index + 1)
      end
    end

    respond_to do |format|
      format.json { render json: { status: 'success' } }
    end
  end

  # POST /manage/website/pages/:page_id/sections/:id/gallery/upload_video
  def upload_video
    @section.gallery_video.attach(params[:video])

    config_updates = {
      'video_title' => params[:video_title],
      'video_autoplay' => params[:video_autoplay] == 'true'
    }

    @section.section_config ||= {}
    @section.section_config.merge!(config_updates)
    @section.instance_variable_set(:@video_just_attached, true)
    @section.save!

    respond_to do |format|
      format.json { render json: { status: 'success' } }
    end
  rescue ActiveRecord::RecordInvalid => e
    # Handle validation errors (e.g., wrong format, size exceeds 50MB)
    respond_to do |format|
      format.json {
        render json: {
          status: 'error',
          error: e.record.errors.full_messages.join(', ')
        }, status: :unprocessable_entity
      }
    end
  rescue StandardError => e
    # Handle other errors
    Rails.logger.error("Video upload error: #{e.message}")
    respond_to do |format|
      format.json {
        render json: {
          status: 'error',
          error: 'Error uploading video'
        }, status: :internal_server_error
      }
    end
  end

  # DELETE /manage/website/pages/:page_id/sections/:id/gallery/remove_video
  def remove_video
    @section.gallery_video.purge if @section.gallery_video.attached?

    respond_to do |format|
      format.json { render json: { status: 'success' } }
    end
  end

  # GET /manage/website/pages/:page_id/sections
  # Renders the page-builder interface initially and is also used by the
  # Stimulus controller (refreshSections) to fetch an updated DOM snippet.
  def index
    respond_to do |format|
      # Full HTML (layout) for normal navigation and JS fetches
      format.html

      # Lightweight JSON representation – currently unused by frontend but
      # helpful for API consumers and specs.
      format.json do
        sections = @page.page_sections.ordered.map { |s| section_json(s) }
        render json: { status: 'success', sections: sections }
      end
    end
  end
  
  def create
    @section = @page.page_sections.build(section_params)
    
    # Use provided position or calculate next position
    @section.position = section_params[:position] || next_position
    
    if @section.save
      # Create page version snapshot
      PageVersion.create_from_page(@page, current_user, "Added #{@section.section_type} section")
      
      respond_to do |format|
        format.json { render json: { status: 'success', section: section_json(@section) } }
        format.html { redirect_to business_manager_website_page_sections_path(@page) }
      end
    else
      respond_to do |format|
        format.json { render json: { status: 'error', errors: @section.errors } }
        format.html { redirect_to business_manager_website_page_sections_path(@page), alert: 'Failed to create section' }
      end
    end
  end
  
  def edit
    respond_to do |format|
      format.html { render partial: 'edit_section_form', locals: { section: @section } }
      format.json { render json: { section: section_json(@section) } }
    end
  end

  def update
    if @section.update(section_params)
      # Create page version snapshot
      PageVersion.create_from_page(@page, current_user, "Updated #{@section.section_type} section")
      
      respond_to do |format|
        format.json { render json: { status: 'success', redirect_url: business_manager_website_page_sections_path(@page), message: 'Section updated successfully!' } }
        format.html { redirect_to business_manager_website_page_sections_path(@page) }
      end
    else
      respond_to do |format|
        format.json { render json: { status: 'error', errors: @section.errors } }
        format.html { redirect_to business_manager_website_page_sections_path(@page), alert: 'Failed to update section' }
      end
    end
  end
  
  def destroy
    section_type = @section.section_type
    @section.destroy
    
    # Reorder remaining sections
    reorder_sections
    
    # Create page version snapshot
    PageVersion.create_from_page(@page, current_user, "Removed #{section_type} section")
    
    respond_to do |format|
      format.json { render json: { status: 'success' } }
      format.html { redirect_to edit_business_manager_website_page_path(@page) }
    end
  end
  
  def reorder
    # Handle both individual section reordering and bulk reordering
    if params[:id].present?
      # Individual section reordering (member route)
      new_position = params[:position].to_i
      
      # Get all sections ordered by position
      sections = @page.page_sections.ordered.to_a
      
      # Remove the section from its current position
      sections.delete(@section)
      
      # Insert it at the new position
      sections.insert(new_position, @section)
      
      # Update all positions
      sections.each_with_index do |section, index|
        section.update(position: index)
      end
      
      # Create page version snapshot
      PageVersion.create_from_page(@page, current_user, "Moved #{@section.section_type} section")
      
      respond_to do |format|
        format.json { render json: { status: 'success' } }
      end
    else
      # Bulk reordering (collection route)
      section_ids = params[:section_ids] || []
      
      section_ids.each_with_index do |id, index|
        section = @page.page_sections.find(id)
        section.update(position: index)
      end
      
      # Create page version snapshot
      PageVersion.create_from_page(@page, current_user, "Reordered page sections")
      
      respond_to do |format|
        format.json { render json: { status: 'success' } }
      end
    end
  end
  
  def move_up
    current_position = @section.position
    return if current_position <= 0
    
    # Swap positions with section above
    section_above = @page.page_sections.where(position: current_position - 1).first
    if section_above
      section_above.update(position: current_position)
      @section.update(position: current_position - 1)
    end
    
    redirect_to edit_business_manager_website_page_path(@page)
  end
  
  def move_down
    current_position = @section.position
    max_position = @page.page_sections.maximum(:position)
    return if current_position >= max_position
    
    # Swap positions with section below
    section_below = @page.page_sections.where(position: current_position + 1).first
    if section_below
      section_below.update(position: current_position)
      @section.update(position: current_position + 1)
    end
    
    redirect_to edit_business_manager_website_page_path(@page)
  end
  
  def duplicate
    new_section = @section.dup
    new_section.position = next_position
    
    if new_section.save
      # Create page version snapshot
      PageVersion.create_from_page(@page, current_user, "Duplicated #{@section.section_type} section")
      
      respond_to do |format|
        format.json { render json: { status: 'success', section: section_json(new_section) } }
        format.html { redirect_to edit_business_manager_website_page_path(@page) }
      end
    else
      respond_to do |format|
        format.json { render json: { status: 'error', errors: new_section.errors } }
        format.html { redirect_to edit_business_manager_website_page_path(@page), alert: 'Failed to duplicate section' }
      end
    end
  end
  

  
  private
  
  def set_page
    @page = current_business.pages.find(params[:page_id])
  end
  
  def set_section
    @section = @page.page_sections.find(params[:id])
  end
  
  def section_params
    # Define allowed content keys for section content
    allowed_content_keys = [
      :title, :subtitle, :description, :content, :image_url, :link_url, :link_text,
      :button_text, :button_url, :heading, :subheading, :text, :items, :layout,
      :show_contact_form, :show_map, :show_hours, :show_social_links,
      :grid_columns, :max_items, :show_pricing, :show_descriptions,
      :company_name, :address, :phone, :email, :hours, :social_links,
      :gallery_layout, :gallery_columns, :gallery_photo_source_mode,
      :show_video, :video_position, :video_title, :video_autoplay,
      :show_hover_effects, :show_photo_titles,
      items: [], social_links: {}
    ]
    
    # Use proper strong parameter filtering for all parameters
    permitted_params = params.require(:page_section).permit(
      :section_type, :position, :active, :custom_css_classes, :animation_type,
      section_config: {}, 
      background_settings: {},
      content: allowed_content_keys
    )
    
    # Handle alternative content parameter sources with proper filtering
    if params[:section_content].present?
      permitted_params[:content] = params.require(:section_content).permit(allowed_content_keys).to_h
    elsif params[:section_content_json].present?
      begin
        parsed_content = JSON.parse(params[:section_content_json])
        # Filter the parsed JSON through strong parameters for security
        if parsed_content.is_a?(Hash)
          temp_params = ActionController::Parameters.new(parsed_content)
          permitted_params[:content] = temp_params.permit(allowed_content_keys).to_h
        else
          # If parsed content is not a hash, convert to string and assign
          permitted_params[:content] = parsed_content.to_s
        end
      rescue JSON::ParserError
        # If JSON parsing fails, keep the original content unchanged
      end
    end
    
    permitted_params
  end
  
  def next_position
    (@page.page_sections.maximum(:position) || -1) + 1
  end
  
  def reorder_sections
    @page.page_sections.ordered.each_with_index do |section, index|
      section.update_column(:position, index)
    end
  end
  
  def section_json(section)
    {
      id: section.id,
      section_type: section.section_type,
      position: section.position,
      content: section.content.to_s,
      config: section.section_config,
      css_classes: section.css_classes,
      active: section.active?
    }
  end

  # Add photo to section with locking
  def add_photo_to_section(section, file, attributes)
    ActiveRecord::Base.transaction do
      locked_section = PageSection.lock.find(section.id)

      if locked_section.gallery_photos.count >= 50
        raise StandardError, "Maximum 50 photos per section"
      end

      photo = locked_section.gallery_photos.build(
        business: locked_section.page.business,
        photo_source: :gallery,
        title: attributes['title'],
        description: attributes['description']
      )

      photo.image.attach(file)
      photo.save!
      photo
    end
  end

  # JSON representation of photo
  def photo_json(photo)
    {
      id: photo.id,
      title: photo.title,
      description: photo.description,
      position: photo.position,
      image_url: photo.image_url(:medium),
      thumb_url: photo.image_url(:thumb)
    }
  end
end 